import Foundation
import Observation
import WebKit

/// Discovers and removes the data iOS lets this app own: its own caches,
/// temp files, URLSession storage, WebView storage and logs.
@MainActor
@Observable
final class CacheService {
    enum Phase: Equatable {
        case idle
        case scanning
        case cleaning
    }

    private(set) var phase: Phase = .idle
    private(set) var groups: [CacheGroup] = []
    private(set) var snapshot: StorageSnapshot = .empty
    private(set) var lastScan: Date?
    private(set) var webRecords = 0

    var selection: Set<CacheKind> = []
    var hasScanned = false

    var removable: Int64 { groups.reduce(0) { $0 + $1.bytes } }
    var selectedBytes: Int64 {
        groups.filter { selection.contains($0.kind) }.reduce(0) { $0 + $1.bytes }
    }
    var isBusy: Bool { phase != .idle }

    func group(for kind: CacheKind) -> CacheGroup? {
        groups.first { $0.kind == kind }
    }

    // MARK: - Scanning

    func scan() async {
        guard phase == .idle else { return }
        phase = .scanning
        let started = Date()

        let discovered = await Task.detached(priority: .userInitiated) {
            CacheService.discover()
        }.value
        let records = await WebViewStore.recordCount()

        groups = discovered.groups.filter { !$0.isEmpty }
        webRecords = records
        snapshot = discovered.snapshot
        snapshot.lastScan = started
        lastScan = started

        // Keep the current selection valid: drop kinds that came back empty.
        selection.formUnion(groups.filter { $0.bytes > 0 && !selection.contains($0.kind) }.map(\.kind))
        selection = selection.filter { kind in groups.contains { $0.kind == kind && $0.bytes > 0 } }
        hasScanned = true
        phase = .idle
    }

    func refreshVolume() {
        let volume = DiskProbe.volume()
        snapshot.deviceTotal = volume.total
        snapshot.deviceFree = volume.free
    }

    /// Fills in the two numbers the container cannot report on its own: what
    /// the app has reclaimed since install, and when that last happened.
    func applyHistory(lifetimeReclaimed: Int64, lastClean: Date?) {
        snapshot.lifetimeReclaimed = lifetimeReclaimed
        snapshot.lastClean = lastClean
    }

    /// Walks the sandbox. Isolated from the actor on purpose so the detached
    /// task can call it without hopping back to the main thread.
    nonisolated private static func discover() -> (groups: [CacheGroup], snapshot: StorageSnapshot) {
        var groups: [CacheGroup] = []

        groups.append(makeGroup(.caches, root: Sandbox.caches))
        groups.append(makeGroup(.temp, root: Sandbox.temp))
        groups.append(makeGroup(.web, root: Sandbox.webKit))
        groups.append(makeGroup(.httpStorage, root: Sandbox.httpStorages))
        groups.append(makeGroup(.logs, root: Sandbox.logs))

        var snapshot = StorageSnapshot()
        let volume = DiskProbe.volume()
        snapshot.deviceTotal = volume.total
        snapshot.deviceFree = volume.free
        snapshot.containerTotal = DeepSize.of(Sandbox.home)
        snapshot.removable = groups.reduce(0) { $0 + $1.bytes }
        snapshot.documents = DeepSize.of(Sandbox.documents)
        snapshot.data = DeepSize.of(Sandbox.appSupport)

        return (groups, snapshot)
    }

    nonisolated private static func makeGroup(_ kind: CacheKind, root: URL) -> CacheGroup {
        guard DiskProbe.exists(root) else { return CacheGroup(kind: kind, items: []) }
        let items = DiskProbe.children(of: root).map { CacheItem(url: $0, kind: kind) }
        return CacheGroup(kind: kind, items: items)
    }

    // MARK: - Cleaning

    @discardableResult
    func clean(kinds: Set<CacheKind>) async -> Int64 {
        guard !isBusy, !kinds.isEmpty else { return 0 }
        phase = .cleaning
        var reclaimed: Int64 = 0

        if kinds.contains(.web) {
            reclaimed += await WebViewStore.purge()
        }

        let roots = kinds.filter { $0 != .web }.compactMap { root(for: $0) }
        let deleted = await Task.detached(priority: .utility) { () -> Int64 in
            var freed: Int64 = 0
            for url in roots { freed += CacheService.purge(in: url) }
            return freed
        }.value

        reclaimed += deleted
        // Drops both the memory and disk halves of URLSession's shared cache.
        URLCache.shared.removeAllCachedResponses()

        let discovered = await Task.detached(priority: .userInitiated) {
            CacheService.discover()
        }.value
        groups = discovered.groups.filter { !$0.isEmpty }
        snapshot = discovered.snapshot
        snapshot.lastScan = Date()
        lastScan = Date()
        selection = []
        phase = .idle
        return max(reclaimed, 0)
    }

    nonisolated private static func purge(in root: URL) -> Int64 {
        guard DiskProbe.exists(root) else { return 0 }
        let before = DeepSize.of(root)
        for child in DiskProbe.children(of: root) {
            let name = child.lastPathComponent
            // Never eat the app's own state or Apple's WebKit support files.
            if Sandbox.protectedNames.contains(name) { continue }
            try? Sandbox.fm.removeItem(at: child)
        }
        return max(before - DeepSize.of(root), 0)
    }

    private func root(for kind: CacheKind) -> URL? {
        switch kind {
        case .caches: return Sandbox.caches
        case .temp: return Sandbox.temp
        case .web: return nil                 // handled by WebViewStore
        case .httpStorage: return Sandbox.httpStorages
        case .logs: return Sandbox.logs
        }
    }
}

/// WKWebsiteDataStore is the only supported way to clear WebView storage, and
/// it is callback based. Main actor because the shared store itself is.
@MainActor
enum WebViewStore {
    static func recordCount() async -> Int {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        return await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().fetchDataRecords(ofTypes: types) { records in
                continuation.resume(returning: records.count)
            }
        }
    }

    static func purge() async -> Int64 {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let store = WKWebsiteDataStore.default()
        let before = await Task.detached(priority: .utility) {
            DeepSize.of(Sandbox.webKit)
        }.value

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
                continuation.resume()
            }
        }

        let after = await Task.detached(priority: .utility) {
            DeepSize.of(Sandbox.webKit)
        }.value
        return max(before - after, 0)
    }
}
