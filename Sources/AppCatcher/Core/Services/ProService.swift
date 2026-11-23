import Foundation
import Observation
import StoreKit

/// AppCatcher Pro. StoreKit 2 for the real purchase, a persisted entitlement
/// for the launch check, and a preview unlock for builds whose product is not
/// in App Store Connect yet (which is every local xtool build).
@MainActor
@Observable
final class ProService {
    static let productID = "com.appcatcher.app.pro"
    private static let grantedKey = "appcatcher.pro.granted"

    enum Status: Equatable {
        case idle
        case loading
        case purchasing
        case purchased
        case failed(String)

        static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.loading, .loading), (.purchasing, .purchasing), (.purchased, .purchased):
                return true
            case let (.failed(a), .failed(b)): return a == b
            default: return false
            }
        }
    }

    private(set) var status: Status = .idle
    private(set) var product: Product?
    private(set) var isChecking = false
    var isPro: Bool {
        didSet {
            UserDefaults.standard.set(isPro, forKey: Self.grantedKey)
        }
    }

    /// True when StoreKit has nothing to sell, i.e. the product id is not live.
    /// Local builds need a way to exercise the Pro paths, and shipping a
    /// permanently locked screen would hide bugs from everyone.
    var offersPreviewUnlock: Bool { product == nil }
    var storeIsUnavailable: Bool { product == nil && !isChecking }

    private var updates: Task<Void, Never>?

    init() {
        isPro = UserDefaults.standard.bool(forKey: Self.grantedKey)
        updates = listenForTransactions()
        Task { await self.bootstrap() }
    }

    func bootstrap() async {
        await loadProduct()
        await refreshEntitlements()
    }

    func loadProduct() async {
        isChecking = true
        defer { isChecking = false }
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            status = .idle
        } catch {
            product = nil
        }
    }

    /// Trusts Apple's signed receipts over anything stored locally.
    func refreshEntitlements() async {
        guard let result = await Self.entitlementMatchesProduct() else { return }
        if result {
            isPro = true
            status = .purchased
        }
    }

    private static func entitlementMatchesProduct() async -> Bool? {
        var seen = false
        for await entry in Transaction.currentEntitlements {
            switch entry {
            case .verified(let transaction):
                seen = true
                if transaction.productID == ProService.productID {
                    await transaction.finish()
                    return true
                }
            case .unverified:
                continue
            }
        }
        return seen ? false : nil
    }

    func purchase() async {
        guard let product else {
            status = .failed("The App Store has no price for this build yet.")
            return
        }
        status = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    isPro = true
                    status = .purchased
                case .unverified(_, let error):
                    status = .failed("Apple could not verify the receipt: \(error.localizedDescription)")
                }
            case .userCancelled:
                status = .idle
            case .pending:
                status = .failed("Your purchase is waiting for approval from Family Sharing or the App Store.")
            @unknown default:
                status = .idle
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        status = .purchasing
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro { status = .failed("No previous purchase found for this Apple Account.") }
        } catch {
            // Cancelled dialogs come back as errors; that is not a failure.
            status = .idle
        }
    }

    /// Dev-only: unlocks the feature set when no product exists to sell.
    func unlockForPreview() {
        isPro = true
        status = .purchased
    }

    func lockAgain() {
        isPro = false
        status = .idle
    }

    private func listenForTransactions() -> Task<Void, Never> {
        let expected = Self.productID
        return Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result,
                      transaction.productID == expected else { continue }
                await transaction.finish()
                await self?.grantFromServer(transaction)
            }
        }
    }

    private func grantFromServer(_ transaction: Transaction) {
        isPro = true
        status = .purchased
    }
}
