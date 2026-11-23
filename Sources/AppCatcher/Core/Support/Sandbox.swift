import Foundation

/// Every path AppCatcher can legitimately touch.
///
/// iOS sandboxes each app to its own container, so "cleaning caches" means the
/// app's own caches, temp files and web data. These are the only roots the
/// scanner walks, and the only ones the archiver will ever write into.
enum Sandbox {
    static let fm = FileManager.default

    static var home: URL { URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true) }

    static var documents: URL { search(.documentDirectory) }

    static var caches: URL { search(.cachesDirectory) }
    static var appSupport: URL { search(.applicationSupportDirectory) }
    static var library: URL { search(.libraryDirectory) }

    static var temp: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    /// HTTP cookie / cache storage written by URLSession.
    static var httpStorages: URL { library.appendingPathComponent("HTTPStorages", isDirectory: true) }
    /// WebKit (WKWebView) data: icons, resource blobs, service workers.
    static var webKit: URL { library.appendingPathComponent("WebKit", isDirectory: true) }
    static var logs: URL { library.appendingPathComponent("Logs", isDirectory: true) }

    // MARK: AppCatcher-owned state (never offered for cleaning)

    static var appCatcherRoot: URL { appSupport.appendingPathComponent("AppCatcher", isDirectory: true) }
    static var backups: URL { appCatcherRoot.appendingPathComponent("Backups", isDirectory: true) }
    static var preRestore: URL { caches.appendingPathComponent("PreRestore", isDirectory: true) }
    static var staging: URL { caches.appendingPathComponent("Staging", isDirectory: true) }

    /// Folders AppCatcher writes for itself. A cleaner that eats its own
    /// database or backup set is worse than no cleaner at all.
    static let protectedNames: Set<String> = ["AppCatcher", "com.apple.WebKit", "PreRestore", "Staging"]

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func exists(_ url: URL) -> Bool {
        fm.fileExists(atPath: url.path)
    }

    private static func search(_ directory: FileManager.SearchPathDirectory) -> URL {
        if let url = fm.urls(for: directory, in: .userDomainMask).first {
            return url
        }
        // Deterministic fallback: the container layout is fixed by iOS.
        let leaf: String
        switch directory {
        case .documentDirectory: leaf = "Documents"
        case .cachesDirectory: leaf = "Library/Caches"
        case .applicationSupportDirectory: leaf = "Library/Application Support"
        case .libraryDirectory: leaf = "Library"
        default: leaf = "Library"
        }
        return home.appendingPathComponent(leaf, isDirectory: true)
    }
}
