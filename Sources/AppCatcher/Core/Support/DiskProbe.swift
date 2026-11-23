import Foundation

/// A leaf file found under one of the sandbox roots.
struct FileStamp {
    var url: URL
    var bytes: Int64
    var modified: Date?
}

/// Read-only disk measurements. Nothing here mutates the filesystem, so the
/// scanner can run as often as the UI wants without side effects.
enum DiskProbe {
    private static let keys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .isRegularFileKey,
        .isDirectoryKey,
        .contentModificationDateKey,
    ]

    /// Allocates-on-disk bytes for a file, directory or missing path.
    static func bytes(at url: URL) -> Int64 {
        if isDirectory(url) {
            return DeepSize.of(url)
        }
        return allocated(url)
    }

    static func allocated(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys) else {
            let attrs = try? Sandbox.fm.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? Int64) ?? Int64((attrs?[.size] as? Int) ?? 0)
        }
        if let total = values.totalFileAllocatedSize { return Int64(total) }
        if let single = values.fileAllocatedSize { return Int64(single) }
        return 0
    }

    static func exists(_ url: URL) -> Bool {
        Sandbox.fm.fileExists(atPath: url.path)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return Sandbox.fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: keys).contentModificationDate
    }

    /// Immediate children, directories first then newest-modified, so the UI
    /// reads "biggest offender" at the top.
    static func children(of url: URL) -> [URL] {
        guard let items = try? Sandbox.fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.sorted { lhs, rhs in
            let l = bytes(at: lhs), r = bytes(at: rhs)
            if l != r { return l > r }
            return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    /// Recursive byte total plus file count in a single walk.
    static func scan(_ root: URL) -> (bytes: Int64, files: Int) {
        if !DiskProbe.isDirectory(root) { return (DiskProbe.allocated(root), 1) }
        guard let walker = Sandbox.fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return (0, 0) }

        var bytes: Int64 = 0
        var files = 0
        for case let fileURL as URL in walker {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            ]) else { continue }
            if values.isRegularFile == true {
                bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                files += 1
            }
        }
        return (bytes, files)
    }

    /// All files below `root`, biggest first. Used by the archive builder.
    static func files(under root: URL, limit: Int = 20_000) -> [FileStamp] {
        guard let walker = Sandbox.fm.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var out: [FileStamp] = []
        for case let fileURL as URL in walker {
            var isDir: ObjCBool = false
            guard Sandbox.fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            out.append(FileStamp(url: fileURL, bytes: allocated(fileURL), modified: modified(fileURL)))
            if out.count >= limit { break }
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    /// Volume capacity. `volumeAvailableCapacityForImportantUsage` is the
    /// number iOS itself shows in Settings, so the UI matches the system.
    static func volume() -> (total: Int64, free: Int64) {
        let url = Sandbox.documents
        guard let values = try? url.resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        ) else {
            let attrs = try? Sandbox.fm.attributesOfFileSystem(forPath: url.path)
            return (Int64((attrs?[.systemSize] as? NSNumber)?.int64Value ?? 0),
                    Int64((attrs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0))
        }
        return (Int64(values.volumeTotalCapacity ?? 0),
                values.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

/// Recursive size, computed off the main actor without building an
/// intermediate array of every URL in the tree.
enum DeepSize {
    static func of(_ root: URL) -> Int64 {
        guard DiskProbe.isDirectory(root) else { return DiskProbe.allocated(root) }
        guard let walker = Sandbox.fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in walker {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            ]) else { continue }
            if values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
