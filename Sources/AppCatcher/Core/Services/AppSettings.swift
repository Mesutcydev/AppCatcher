import Foundation
import Observation

/// User-controlled behaviour, persisted in `UserDefaults` on every change.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    enum AutoCleanInterval: Int, CaseIterable, Identifiable {
        case daily = 1
        case weekly = 7
        case fortnightly = 14
        case monthly = 30

        var id: Int { rawValue }
        var label: String {
            switch self {
            case .daily: return "Every day"
            case .weekly: return "Every week"
            case .fortnightly: return "Every 2 weeks"
            case .monthly: return "Every month"
            }
        }
    }

    var autoCleanEnabled: Bool { didSet { write(autoCleanEnabled, for: .autoClean) } }
    var autoCleanInterval: AutoCleanInterval { didSet { write(autoCleanInterval.rawValue, for: .autoCleanDays) } }
    var autoCleanWebData: Bool { didSet { write(autoCleanWebData, for: .autoCleanWeb) } }

    var includeCachesInBackups: Bool { didSet { write(includeCachesInBackups, for: .backupCaches) } }
    var confirmBeforeRestore: Bool { didSet { write(confirmBeforeRestore, for: .confirmRestore) } }
    var hapticsEnabled: Bool { didSet { write(hapticsEnabled, for: .haptics) } }

    var hasCompletedOnboarding: Bool { didSet { write(hasCompletedOnboarding, for: .onboarded) } }
    var lifetimeReclaimed: Int64 { didSet { write(lifetimeReclaimed, for: .lifetime) } }
    var lastCleanAt: Date? { didSet { write(lastCleanAt?.timeIntervalSince1970, for: .lastClean) } }
    var lastAutoCleanAt: Date? { didSet { write(lastAutoCleanAt?.timeIntervalSince1970, for: .lastAutoClean) } }

    init(store: UserDefaults = .standard) {
        defaults = store
        autoCleanEnabled = store.bool(forKey: Key.autoClean.rawValue)
        autoCleanInterval = AutoCleanInterval(
            rawValue: store.integer(forKey: Key.autoCleanDays.rawValue)
        ) ?? .weekly
        autoCleanWebData = store.object(forKey: Key.autoCleanWeb.rawValue) as? Bool ?? false
        includeCachesInBackups = store.bool(forKey: Key.backupCaches.rawValue)
        confirmBeforeRestore = store.object(forKey: Key.confirmRestore.rawValue) as? Bool ?? true
        hapticsEnabled = store.object(forKey: Key.haptics.rawValue) as? Bool ?? true
        hasCompletedOnboarding = store.bool(forKey: Key.onboarded.rawValue)
        lifetimeReclaimed = Int64(store.integer(forKey: Key.lifetime.rawValue))
        if let stamp = store.object(forKey: Key.lastClean.rawValue) as? Double {
            lastCleanAt = Date(timeIntervalSince1970: stamp)
        }
        if let stamp = store.object(forKey: Key.lastAutoClean.rawValue) as? Double {
            lastAutoCleanAt = Date(timeIntervalSince1970: stamp)
        }
    }

    /// True when the schedule says it is due. Auto-clean runs when the app is
    /// opened rather than in the background: iOS only wakes apps that hold a
    /// background entitlement, and pretending otherwise would be a lie in the UI.
    var autoCleanIsDue: Bool {
        guard autoCleanEnabled else { return false }
        guard let last = lastAutoCleanAt else { return true }
        return Date().timeIntervalSince(last) >= Double(autoCleanInterval.rawValue * 86_400)
    }

    var nextAutoCleanDate: Date? {
        guard autoCleanEnabled else { return nil }
        let anchor = lastAutoCleanAt ?? .now
        return anchor.addingTimeInterval(Double(autoCleanInterval.rawValue * 86_400))
    }

    func markAutoClean() {
        lastAutoCleanAt = .now
    }

    func addReclaimed(_ bytes: Int64) {
        lifetimeReclaimed += max(bytes, 0)
        lastCleanAt = .now
    }

    private func write(_ value: Any?, for key: Key) {
        if let value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    private enum Key: String {
        case autoClean = "appcatcher.autoclean.enabled"
        case autoCleanDays = "appcatcher.autoclean.days"
        case autoCleanWeb = "appcatcher.autoclean.web"
        case backupCaches = "appcatcher.backup.caches"
        case confirmRestore = "appcatcher.confirm.restore"
        case haptics = "appcatcher.haptics"
        case onboarded = "appcatcher.onboarded"
        case lifetime = "appcatcher.lifetime.reclaimed"
        case lastClean = "appcatcher.last.clean"
        case lastAutoClean = "appcatcher.last.autoclean"
    }
}

/// Rolling history of everything AppCatcher has done, so the dashboard can
/// show cause and effect instead of a bare number.
@MainActor
@Observable
final class ActivityLog {
    private(set) var events: [ActivityEvent] = []
    private let limit = 60
    private let file: URL

    init() {
        Sandbox.ensure(Sandbox.appCatcherRoot)
        file = Sandbox.appCatcherRoot.appendingPathComponent("activity.json")
        load()
    }

    func record(_ kind: ActivityKind, _ title: String, detail: String, bytes: Int64 = 0) {
        events.insert(ActivityEvent(kind: kind, title: title, detail: detail, bytes: bytes), at: 0)
        if events.count > limit { events = Array(events.prefix(limit)) }
        save()
    }

    func clear() {
        events = []
        save()
    }

    var lastClean: ActivityEvent? { events.first { $0.kind == .cleaned } }
    var lastBackup: ActivityEvent? { events.first { $0.kind == .backedUp } }

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder.catcher.decode([ActivityEvent].self, from: data)
        else { return }
        events = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder.catcher.encode(events) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
