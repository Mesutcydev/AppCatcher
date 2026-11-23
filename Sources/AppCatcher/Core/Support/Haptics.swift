import UIKit

/// Haptics are part of the product, not decoration: the tick when a selection
/// lands, the thud when 300 MB disappears, the soft confirm when a backup
/// seals.
///
/// Calls are legal from any thread — UIKit generators are built and fired on
/// the main thread here — and the whole thing is a no-op when the user turns
/// haptic feedback off in Settings.
enum Haptics {
    static var isEnabled = true

    static func tap() {
        main { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    static func select() {
        main { UISelectionFeedbackGenerator().selectionChanged() }
    }

    static func scanComplete() {
        main { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    static func cleaned() {
        main { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
        delayed(0.11) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    static func saved() {
        main { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    static func warning() {
        main { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    }

    static func failed() {
        main { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }

    private static func main(_ body: @escaping () -> Void) {
        guard isEnabled else { return }
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }

    private static func delayed(_ seconds: TimeInterval, _ body: @escaping () -> Void) {
        guard isEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: body)
    }
}
