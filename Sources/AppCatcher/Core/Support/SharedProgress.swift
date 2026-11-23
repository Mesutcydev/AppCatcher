import Foundation

/// A `Double` in 0...1 that a worker thread may write while the main actor
/// reads it. `Sendable` by construction: every access takes the lock.
final class SharedProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double
    private var complete = false

    init(_ value: Double = 0) { self.value = value }

    func set(_ newValue: Double) {
        lock.lock()
        value = min(max(newValue, 0), 1)
        lock.unlock()
    }

    var current: Double {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    /// Set once the worker returns or throws, so the polling loop can stop.
    func finish() {
        lock.lock()
        complete = true
        lock.unlock()
    }

    var isComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return complete
    }
}
