import Foundation
import Observation

/// Owns the `.catcher` archive set: create, list, verify, restore, import,
/// export, delete.
@MainActor
@Observable
final class BackupService {
    enum Phase: Equatable {
        case idle
        case creating
        case restoring
        case verifying
    }

    private(set) var records: [BackupRecord] = []
    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    var errorMessage: String?

    /// Free builds keep one archive. Pro keeps the whole history.
    static let freeHistoryLimit = 1

    var totalBytes: Int64 { records.reduce(0) { $0 + $1.bytes } }
    var latest: BackupRecord? { records.max(by: { $0.createdAt < $1.createdAt }) }
    var isBusy: Bool { phase != .idle }

    init() {
        Sandbox.ensure(Sandbox.backups)
        reload()
    }

    // MARK: - Catalogue

    /// Rebuilds the list from disk. The archive files are the source of truth,
    /// so a reinstall or a Files-app edit cannot desync the UI.
    func reload() {
        Sandbox.ensure(Sandbox.backups)
        let urls = (try? Sandbox.fm.contentsOfDirectory(
            at: Sandbox.backups,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var found: [BackupRecord] = []
        for url in urls where url.pathExtension == "catcher" {
            guard let header = try? CatcherArchive.readHeader(at: url) else { continue }
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            found.append(BackupRecord(
                name: header.label,
                createdAt: header.createdAt,
                fileName: url.lastPathComponent,
                bytes: size,
                originalBytes: header.sourceBytes,
                fileCount: header.fileCount,
                isEncrypted: header.isEncrypted,
                includesCaches: header.includesCaches,
                note: header.note,
                appVersion: header.appVersion
            ))
        }
        records = found.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Create

    @discardableResult
    func create(
        name: String,
        note: String = "",
        password: String?,
        includeCaches: Bool,
        isPro: Bool
    ) async throws -> BackupRecord {
        guard phase == .idle else { throw CatcherError.ioFailed("AppCatcher is already busy.") }
        if !isPro && !records.isEmpty {
            throw CatcherError.proOnly("Keeping more than one backup")
        }
        if (password?.isEmpty == false) && !isPro {
            throw CatcherError.proOnly("Encrypted backups")
        }

        phase = .creating
        progress = 0
        defer { phase = .idle }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmedName.isEmpty ? "Backup \(Date().shortStamp)" : trimmedName
        let fileURL = Sandbox.backups.appendingPathComponent("\(Date().fileStamp).catcher")
        let roots: [ArchiveRoot] = includeCaches ? [.documents, .appData, .caches] : [.documents, .appData]
        let pass = (password?.isEmpty == false) ? password : nil

        let built = try await run(phase: .creating) { reporter in
            try CatcherArchive.build(
                label: label,
                note: note,
                password: pass,
                roots: roots,
                to: fileURL,
                progress: { reporter.set($0) }
            )
        }

        let record = BackupRecord(
            name: label,
            createdAt: built.header.createdAt,
            fileName: built.url.lastPathComponent,
            bytes: built.bytes,
            originalBytes: built.header.sourceBytes,
            fileCount: built.header.fileCount,
            isEncrypted: built.header.isEncrypted,
            includesCaches: built.header.includesCaches,
            note: note,
            appVersion: AppInfo.version,
            durationSeconds: 0
        )
        records.insert(record, at: 0)
        pruneHistory(isPro: isPro)
        return record
    }

    private func pruneHistory(isPro: Bool) {
        guard !isPro, records.count > Self.freeHistoryLimit else { return }
        for stale in records.dropFirst(Self.freeHistoryLimit) {
            try? Sandbox.fm.removeItem(at: stale.url)
        }
        records = Array(records.prefix(Self.freeHistoryLimit))
    }

    // MARK: - Verify

    func verify(_ record: BackupRecord, password: String?) async throws -> VerifyReport {
        guard phase == .idle else { throw CatcherError.ioFailed("AppCatcher is already busy.") }
        let url = record.url
        let pass = password

        let report = try await run(phase: .verifying) { reporter in
            let result = try CatcherArchive.verify(at: url, password: pass)
            reporter.set(1)
            return result
        }

        if let index = records.firstIndex(where: { $0.id == record.id }), report.ok {
            records[index].verifiedAt = .now
        }
        return report
    }

    /// Runs `work` off the main actor while mirroring its progress bar.
    /// The reporter is a lock-guarded box, so the worker thread never touches
    /// actor-isolated state directly.
    private func run<T>(phase newPhase: Phase, _ work: @escaping @Sendable (SharedProgress) throws -> T) async throws -> T {
        progress = 0
        phase = newPhase
        defer { phase = .idle }

        let reporter = SharedProgress()
        let task = Task.detached(priority: .userInitiated) { () -> T in
            defer { reporter.finish() }
            return try work(reporter)
        }
        while !reporter.isComplete {
            progress = reporter.current
            if Task.isCancelled { task.cancel(); break }
            try? await Task.sleep(for: .milliseconds(70))
        }
        do {
            let value = try await task.value
            progress = 1
            return value
        } catch {
            progress = 0
            throw error
        }
    }

    // MARK: - Restore

    struct RestoreOutcome {
        var files: Int
        var bytes: Int64
        var guardURL: URL?
    }

    /// Writes an archive back into the container. The files that were there
    /// first are moved aside once, so a bad restore is not a data loss event.
    func restore(_ record: BackupRecord, password: String?) async throws -> RestoreOutcome {
        guard phase == .idle else { throw CatcherError.ioFailed("AppCatcher is already busy.") }
        guard DiskProbe.exists(record.url) else {
            throw CatcherError.ioFailed("That backup file is no longer in the container.")
        }

        let snapshotURL = try Self.protectCurrentDocuments()
        let url = record.url
        let pass = password

        let report = try await run(phase: .restoring) { reporter in
            try CatcherArchive.extract(from: url, password: pass, progress: { reporter.set($0) })
        }

        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        return RestoreOutcome(files: report.written, bytes: report.bytes, guardURL: snapshotURL)
    }

    private static func protectCurrentDocuments() throws -> URL? {
        let documents = Sandbox.documents
        guard DiskProbe.exists(documents), DeepSize.of(documents) > 0 else { return nil }
        Sandbox.ensure(Sandbox.preRestore)
        let target = Sandbox.preRestore.appendingPathComponent(Date().fileStamp, isDirectory: true)
        do {
            try Sandbox.fm.moveItem(at: documents, to: target)
            Sandbox.ensure(documents)
            return target
        } catch {
            // A failed move must not block the restore: fall back to copying.
            Sandbox.ensure(target)
            for child in DiskProbe.children(of: documents) {
                try? Sandbox.fm.copyItem(at: child, to: target.appendingPathComponent(child.lastPathComponent))
            }
            return target
        }
    }

    /// Pre-restore copies are a safety net, not content. Keep the newest.
    func clearRestoreGuards() {
        guard let guards = try? Sandbox.fm.contentsOfDirectory(
            at: Sandbox.preRestore, includingPropertiesForKeys: nil
        ) else { return }
        for folder in guards { try? Sandbox.fm.removeItem(at: folder) }
    }

    var restoreGuardBytes: Int64 { DeepSize.of(Sandbox.preRestore) }

    // MARK: - Import / export

    /// Copies a `.catcher` file picked with the system file importer into the
    /// backups folder and indexes it.
    @discardableResult
    func importArchive(from source: URL, isPro: Bool) throws -> BackupRecord {
        let secured = source.startAccessingSecurityScopedResource()
        defer { if secured { source.stopAccessingSecurityScopedResource() } }

        guard let header = try? CatcherArchive.readHeader(at: source) else {
            throw CatcherError.notAnArchive
        }
        if !isPro && !records.isEmpty {
            throw CatcherError.proOnly("Importing more than one backup")
        }

        Sandbox.ensure(Sandbox.backups)
        let name = "\(Date().fileStamp).catcher"
        let target = Sandbox.backups.appendingPathComponent(name)
        if DiskProbe.exists(target) { try? Sandbox.fm.removeItem(at: target) }
        try Sandbox.fm.copyItem(at: source, to: target)

        let size = Int64((try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let record = BackupRecord(
            name: header.label,
            createdAt: header.createdAt,
            fileName: name,
            bytes: size,
            originalBytes: header.sourceBytes,
            fileCount: header.fileCount,
            isEncrypted: header.isEncrypted,
            includesCaches: header.includesCaches,
            note: header.note,
            appVersion: header.appVersion
        )
        records.insert(record, at: 0)
        pruneHistory(isPro: isPro)
        return record
    }

    func delete(_ record: BackupRecord) {
        try? Sandbox.fm.removeItem(at: record.url)
        records.removeAll { $0.id == record.id }
    }
}

extension Date {
    /// `2026-11-23T08-41` — sortable and safe as a file name.
    var fileStamp: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'at'HH-mm"
        return formatter.string(from: self)
    }

    /// `Nov 23, 08:41` — what the UI shows.
    var shortStamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}
