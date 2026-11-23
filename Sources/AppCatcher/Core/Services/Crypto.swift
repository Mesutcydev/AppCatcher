import CryptoKit
import Foundation

/// Password-based key derivation and authenticated encryption for `.catcher`
/// archives.
///
/// CryptoKit ships AES-GCM and HMAC but no PBKDF2, so the KDF is implemented
/// here on top of `HMAC<SHA256>`. It follows RFC 8018 §5.2 for the case where
/// dkLen (32) fits in a single hash output, which is the only case the archive
/// format uses.
enum CatcherCrypto {
    static let keyBytes = 32
    static let saltBytes = 16
    static let nonceBytes = 12
    static let defaultIterations = 120_000

    // MARK: - KDF

    static func deriveKey(password: String, salt: Data, iterations: Int) -> SymmetricKey {
        let passphrase = Data(password.utf8)
        let blockInfo = salt + [0, 0, 0, 1]          // salt || i, i = 1
        var previous = hmac(password: passphrase, data: blockInfo)
        var result = previous

        guard iterations > 1 else { return SymmetricKey(data: result) }
        for _ in 2...iterations {
            previous = hmac(password: passphrase, data: previous)
            xor(&result, with: previous)
        }
        return SymmetricKey(data: result)
    }

    private static func hmac(password: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: password)))
    }

    private static func xor(_ lhs: inout Data, with rhs: Data) {
        guard lhs.count == rhs.count else { return }
        var a = [UInt8](lhs)
        let b = [UInt8](rhs)
        for index in a.indices { a[index] ^= b[index] }
        lhs = Data(a)
    }

    // MARK: - Sealing

    /// AES-GCM box laid out as `nonce || ciphertext || tag`, with the chunk
    /// index bound in as associated data so reordered chunks fail to open.
    static func sealChunk(_ plaintext: Data, key: SymmetricKey, index: Int) throws -> Data {
        let sealed = try AES.GCM.seal(
            plaintext,
            using: key,
            nonce: AES.GCM.Nonce(),
            authenticating: context(index)
        )
        guard let combined = sealed.combined, combined.count > nonceBytes else {
            throw CatcherError.truncatedArchive
        }
        return combined
    }

    static func openChunk(_ box: Data, key: SymmetricKey, index: Int) throws -> Data {
        guard box.count > nonceBytes + 16 else { throw CatcherError.truncatedArchive }
        let sealed = try AES.GCM.SealedBox(combined: box)
        return try AES.GCM.open(sealed, using: key, authenticating: context(index))
    }

    private static func context(_ index: Int) -> Data {
        var value = UInt32(truncatingIfNeeded: index).bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    // MARK: - Digests

    static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        arc4random_buf(&bytes, count)
        return Data(bytes)
    }
}

/// Errors surfaced to the UI. Everything the archive format can reject.
enum CatcherError: LocalizedError, Equatable {
    case notAnArchive
    case unsupportedVersion(Int)
    case truncatedArchive
    case wrongPassword
    case checksumMismatch(String)
    case nothingToBackUp
    case sourceTooLarge(Int64)
    case proOnly(String)
    case ioFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAnArchive: return "That file is not an AppCatcher backup."
        case let .unsupportedVersion(v): return "This backup uses format v\(v), newer than this build of AppCatcher."
        case .truncatedArchive: return "The backup is incomplete or corrupted."
        case .wrongPassword: return "That password does not match this backup."
        case let .checksumMismatch(path): return "Integrity check failed for \(path)."
        case .nothingToBackUp: return "There is nothing in the container to back up yet."
        case let .sourceTooLarge(bytes):
            return "Source data is \(ByteFormat.string(bytes)). One archive is capped at 1 GB."
        case let .proOnly(feature): return "\(feature) needs AppCatcher Pro."
        case let .ioFailed(message): return message
        }
    }
}
