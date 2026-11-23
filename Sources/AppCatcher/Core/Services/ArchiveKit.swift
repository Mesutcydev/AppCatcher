import Compression
import Foundation

// MARK: - Format
//
// A `.catcher` file is a single self-describing archive:
//
//   magic "ACBA" | version u8 | flags u8 (bit0 = encrypted) | reserved u16
//   payloadLength u64 | headerLength u32 | header JSON | payload
//
// The payload is the concatenation of every stored file, each one LZFSE
// compressed (or raw when compression would inflate it). When a password is
// set, the payload is AES-256-GCM sealed in 4 MiB chunks, each chunk prefixed
// with its length and bound to its position so reordering is detected.

struct ArchiveEntry: Codable, Hashable {
    /// Root label, e.g. "Documents". Decides where a file lands on restore.
    var root: String
    /// Path inside that root, "/" separated.
    var path: String
    var uncompressedSize: Int64
    var storedSize: Int64
    var payloadOffset: Int64
    var sha256: String
    var codec: String
    var modified: Date?

    var decodedPath: String { path }
    var logicalPath: String { "\(root)/\(path)" }
}

struct ArchiveEncryption: Codable, Hashable {
    var kdf: String
    var iterations: Int
    var salt: String
    var chunkSize: Int
}

struct ArchiveHeader: Codable, Hashable {
    var formatVersion: Int
    var label: String
    var note: String
    var appVersion: String
    var createdAt: Date
    var sourceBytes: Int64
    var payloadBytes: Int64
    var includesCaches: Bool
    var deviceModel: String
    var encryption: ArchiveEncryption?
    var entries: [ArchiveEntry]

    var fileCount: Int { entries.count }
    var isEncrypted: Bool { encryption != nil }
}

struct BuiltArchive {
    var url: URL
    var header: ArchiveHeader
    var bytes: Int64
}

enum ArchiveRoot: String, CaseIterable {
    case documents = "Documents"
    case caches = "Caches"
    case appData = "AppData"

    var url: URL {
        switch self {
        case .documents: return Sandbox.documents
        case .caches: return Sandbox.caches
        case .appData: return Sandbox.appSupport
        }
    }
}

// MARK: - Reader / writer

enum CatcherArchive {
    static let magic: [UInt8] = Array("ACBA".utf8)
    static let version = 1
    static let chunkSize = 4 * 1024 * 1024
    static let maxSourceBytes: Int64 = 1_024 * 1024 * 1024

    // MARK: Build

    static func build(
        label: String,
        note: String = "",
        password: String?,
        roots: [ArchiveRoot],
        to destination: URL,
        progress: @escaping (Double) -> Void = { _ in }
    ) throws -> BuiltArchive {
        Sandbox.ensure(destination.deletingLastPathComponent())

        var collected: [(root: ArchiveRoot, stamp: FileStamp)] = []
        var sourceBytes: Int64 = 0
        for root in roots {
            guard DiskProbe.exists(root.url) else { continue }
            for stamp in DiskProbe.files(under: root.url) {
                collected.append((root, stamp))
                sourceBytes += stamp.bytes
            }
        }
        guard !collected.isEmpty else { throw CatcherError.nothingToBackUp }
        guard sourceBytes <= maxSourceBytes else { throw CatcherError.sourceTooLarge(sourceBytes) }

        // ---- payload ----------------------------------------------------
        var payload = Data()
        payload.reserveCapacity(Int(min(sourceBytes, maxSourceBytes)))
        var entries: [ArchiveEntry] = []

        let totalWork = max(collected.count, 1)
        for (index, item) in collected.enumerated() {
            guard let raw = try? Data(contentsOf: item.stamp.url, options: .mappedIfSafe) else { continue }
            let digest = CatcherCrypto.hex(CatcherCrypto.sha256(raw))
            let compressed = CompressionBox.compress(raw)
            let useCompressed = compressed.count < raw.count
            let stored = useCompressed ? compressed : raw

            entries.append(ArchiveEntry(
                root: item.root.rawValue,
                path: relativePath(for: item.stamp.url, root: item.root),
                uncompressedSize: Int64(raw.count),
                storedSize: Int64(stored.count),
                payloadOffset: Int64(payload.count),
                sha256: digest,
                codec: useCompressed ? "lzfse" : "raw",
                modified: item.stamp.modified
            ))
            payload.append(stored)
            progress(Double(index + 1) / Double(totalWork))
        }
        guard !entries.isEmpty else { throw CatcherError.nothingToBackUp }

        // ---- optional encryption ---------------------------------------
        var encryption: ArchiveEncryption?
        if let password, !password.isEmpty {
            let salt = CatcherCrypto.randomBytes(CatcherCrypto.saltBytes)
            let key = CatcherCrypto.deriveKey(
                password: password,
                salt: salt,
                iterations: CatcherCrypto.defaultIterations
            )
            var sealedPayload = Data()
            let bytes = [UInt8](payload)
            let chunks = max(1, (bytes.count + chunkSize - 1) / chunkSize)
            for chunkIndex in 0..<chunks {
                let start = chunkIndex * chunkSize
                let end = min(start + chunkSize, bytes.count)
                let slice = Data(bytes[start..<max(start, end)])
                let box = try CatcherCrypto.sealChunk(slice, key: key, index: chunkIndex)
                var length = UInt32(box.count).bigEndian
                sealedPayload.append(withUnsafeBytes(of: &length) { Data($0) })
                sealedPayload.append(box)
                progress(0.5 + 0.5 * Double(chunkIndex + 1) / Double(chunks))
            }
            payload = sealedPayload
            encryption = ArchiveEncryption(
                kdf: "pbkdf2-sha256",
                iterations: CatcherCrypto.defaultIterations,
                salt: salt.base64EncodedString(),
                chunkSize: chunkSize
            )
        }

        let payloadBytes = Int64(payload.count)
        var header = ArchiveHeader(
            formatVersion: version,
            label: label,
            note: note,
            appVersion: AppInfo.version,
            createdAt: .now,
            sourceBytes: sourceBytes,
            payloadBytes: payloadBytes,
            includesCaches: roots.contains(.caches),
            deviceModel: DeviceIdentity.marketingName,
            encryption: encryption,
            entries: entries
        )
        header.entries = entries.sorted { $0.logicalPath < $1.logicalPath }

        // ---- write ------------------------------------------------------
        let headerData = try JSONEncoder.catcher.encode(header)

        var out = Data()
        out.append(contentsOf: magic)
        out.append(UInt8(version))
        out.append(encryption == nil ? 0 : 1)
        out.append(contentsOf: [0, 0])                      // reserved
        out.append(uint64: UInt64(payloadBytes))
        out.append(uint32: UInt32(headerData.count))
        out.append(headerData)
        out.append(payload)

        try out.write(to: destination, options: .atomic)
        header.payloadBytes = payloadBytes
        return BuiltArchive(url: destination, header: header, bytes: Int64(out.count))
    }

    // MARK: Header

    static func readHeader(at url: URL) throws -> ArchiveHeader {
        let file = try Data(contentsOf: url, options: .mappedIfSafe)
        return try parseHeader(in: file)
    }

    private static func parseHeader(in file: Data) throws -> ArchiveHeader {
        guard file.count > 20 else { throw CatcherError.truncatedArchive }
        let head = [UInt8](file.prefix(20))
        guard Array(head[0..<4]) == magic else { throw CatcherError.notAnArchive }
        let writtenVersion = Int(head[4])
        guard writtenVersion <= version else { throw CatcherError.unsupportedVersion(writtenVersion) }

        let payloadBytes = Int64(file.value(UInt64.self, at: 8))
        let headerLength = Int(file.value(UInt32.self, at: 16))
        guard headerLength > 0, 20 + headerLength <= file.count else { throw CatcherError.truncatedArchive }

        let headerData = file.subdata(in: 20..<(20 + headerLength))
        let header = try JSONDecoder.catcher.decode(ArchiveHeader.self, from: headerData)
        guard header.payloadBytes == payloadBytes || payloadBytes == 0 else {
            throw CatcherError.truncatedArchive
        }
        return header
    }

    // MARK: Payload access

    /// Returns the decompressed bytes of one entry.
    static func payload(at url: URL, header: ArchiveHeader, password: String?) throws -> Data {
        let file = try Data(contentsOf: url, options: .mappedIfSafe)
        let headerLength = Int(file.value(UInt32.self, at: 16))
        let start = 20 + headerLength
        guard start <= file.count else { throw CatcherError.truncatedArchive }
        var blob = file.subdata(in: start..<file.count)
        if header.isEncrypted {
            blob = try decrypt(blob, header: header, password: password)
        }
        return blob
    }

    static func extract(
        from url: URL,
        password: String?,
        into baseDirectory: URL? = nil,
        roots: [ArchiveRoot] = ArchiveRoot.allCases,
        progress: @escaping (Double) -> Void = { _ in }
    ) throws -> ExtractReport {
        let header = try readHeader(at: url)
        let blob = try payload(at: url, header: header, password: password)
        let allowed = Set(roots.map(\.rawValue))

        var report = ExtractReport(written: 0, skipped: 0, bytes: 0)
        let entries = header.entries.filter { allowed.contains($0.root) }
        let total = max(entries.count, 1)

        for (index, entry) in entries.enumerated() {
            let rootURL = (baseDirectory ?? ArchiveRoot(rawValue: entry.root)?.url ?? Sandbox.documents)
            let target = rootURL.appendingRelative(entry.path)
            guard entry.payloadOffset >= 0,
                  entry.payloadOffset + entry.storedSize <= Int64(blob.count) else {
                throw CatcherError.truncatedArchive
            }
            let stored = blob.subdata(
                in: Int(entry.payloadOffset)..<(Int(entry.payloadOffset + entry.storedSize))
            )
            let raw = entry.codec == "lzfse" ? CompressionBox.decompress(stored) : stored
            guard raw.count == Int(entry.uncompressedSize) else {
                throw CatcherError.checksumMismatch(entry.logicalPath)
            }
            guard CatcherCrypto.hex(CatcherCrypto.sha256(raw)) == entry.sha256 else {
                throw CatcherError.checksumMismatch(entry.logicalPath)
            }

            Sandbox.ensure(target.deletingLastPathComponent())
            try raw.write(to: target, options: .atomic)
            report.written += 1
            report.bytes += Int64(raw.count)
            progress(Double(index + 1) / Double(total))
        }
        report.skipped = header.entries.count - report.written
        return report
    }

    /// Opens the archive and checks every stored byte without writing anything.
    static func verify(at url: URL, password: String?) throws -> VerifyReport {
        let started = Date()
        let header = try readHeader(at: url)
        let blob = try payload(at: url, header: header, password: password)
        var failures: [String] = []
        for entry in header.entries {
            guard entry.payloadOffset + entry.storedSize <= Int64(blob.count) else {
                failures.append(entry.logicalPath)
                continue
            }
            let stored = blob.subdata(
                in: Int(entry.payloadOffset)..<(Int(entry.payloadOffset + entry.storedSize))
            )
            let raw = entry.codec == "lzfse" ? CompressionBox.decompress(stored) : stored
            if raw.count != Int(entry.uncompressedSize)
                || CatcherCrypto.hex(CatcherCrypto.sha256(raw)) != entry.sha256 {
                failures.append(entry.logicalPath)
            }
        }
        return VerifyReport(
            header: header,
            ok: failures.isEmpty,
            failures: failures,
            seconds: Date().timeIntervalSince(started)
        )
    }

    // MARK: - Internals

    private static func decrypt(_ blob: Data, header: ArchiveHeader, password: String?) throws -> Data {
        guard let info = header.encryption else { return blob }
        guard let pass = password, !pass.isEmpty else { throw CatcherError.wrongPassword }
        guard let salt = Data(base64Encoded: info.salt) else { throw CatcherError.truncatedArchive }

        let key = CatcherCrypto.deriveKey(
            password: pass,
            salt: salt,
            iterations: max(1, info.iterations)
        )
        var plain = Data()
        var offset = 0
        var chunkIndex = 0
        while offset + 4 <= blob.count {
            let length = Int(blob.value(UInt32.self, at: offset))
            let boxStart = offset + 4
            guard length > 0, boxStart + length <= blob.count else { throw CatcherError.truncatedArchive }
            let box = blob.subdata(in: boxStart..<(boxStart + length))
            do {
                plain.append(try CatcherCrypto.openChunk(box, key: key, index: chunkIndex))
            } catch {
                throw CatcherError.wrongPassword
            }
            offset = boxStart + length
            chunkIndex += 1
        }
        guard !plain.isEmpty || header.sourceBytes == 0 else { throw CatcherError.truncatedArchive }
        return plain
    }

    private static func relativePath(for file: URL, root: ArchiveRoot) -> String {
        let base = root.url.standardizedFileURL.path
        let target = file.standardizedFileURL.path
        if target.hasPrefix(base + "/") {
            return String(target.dropFirst(base.count + 1))
        }
        return file.lastPathComponent
    }
}

struct ExtractReport {
    var written: Int
    var skipped: Int
    var bytes: Int64
}

struct VerifyReport {
    var header: ArchiveHeader
    var ok: Bool
    var failures: [String]
    var seconds: Double
}

// MARK: - Compression

enum CompressionBox {
    static func compress(_ data: Data) -> Data {
        guard !data.isEmpty else { return data }
        var output = Data()
        do {
            let filter = try OutputFilter(
                .compress,
                using: .lzfse,
                bufferCapacity: 1 << 16,
                writingTo: { chunk in if let chunk { output.append(chunk) } }
            )
            try filter.write(data)
            try filter.finalize()
            return output
        } catch {
            return data
        }
    }

    static func decompress(_ data: Data) -> Data {
        guard !data.isEmpty else { return data }
        var output = Data()
        do {
            let cursor = ByteCursor(data)
            let filter = try InputFilter<Data>(
                .decompress,
                using: .lzfse,
                bufferCapacity: 1 << 16,
                readingFrom: { count in cursor.next(count) }
            )
            while let chunk = try filter.readData(ofLength: 1 << 16) {
                output.append(chunk)
            }
            return output
        } catch {
            return Data()
        }
    }
}

/// Feeds a `Data` to `InputFilter` in slices.
private final class ByteCursor {
    private let source: Data
    private var offset = 0

    init(_ source: Data) { self.source = source }

    func next(_ count: Int) -> Data? {
        guard offset < source.count else { return nil }
        let end = Swift.min(offset + Swift.max(count, 1), source.count)
        let slice = source.subdata(in: offset..<end)
        offset = end
        return slice
    }
}

// MARK: - Small helpers

extension JSONEncoder {
    static let catcher: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let catcher: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}

private extension Data {
    /// Big-endian scalar read at a byte offset.
    func value<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        let width = MemoryLayout<T>.size
        guard offset >= 0, offset + width <= count else { return 0 }
        let bytes = [UInt8](subdata(in: offset..<(offset + width)))
        var value = T.zero
        for byte in bytes {
            value = (value << 8) | T(byte)
        }
        return value
    }

    mutating func append(uint32 value: UInt32) {
        var big = value.bigEndian
        append(Swift.withUnsafeBytes(of: &big) { Data($0) })
    }

    mutating func append(uint64 value: UInt64) {
        var big = value.bigEndian
        append(Swift.withUnsafeBytes(of: &big) { Data($0) })
    }
}

extension URL {
    /// Appends a "/"-separated relative path, rejecting traversal.
    func appendingRelative(_ path: String) -> URL {
        let pieces = path
            .split(separator: "/")
            .map(String.init)
            .filter { $0 != "." && $0 != ".." && !$0.isEmpty }
        return pieces.reduce(standardizedFileURL) { $0.appendingPathComponent($1) }
    }
}

enum DeviceIdentity {
    /// A readable machine name for the backup manifest, without pulling in
    /// UIKit's device identifiers.
    static var marketingName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let code = mirror.children.reduce(into: "") { result, child in
            guard let byte = child.value as? Int8, byte != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(bitPattern: byte))))
        }
        return code.isEmpty ? "iOS device" : code
    }
}
