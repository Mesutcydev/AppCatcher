import StoreKit
import SwiftUI

/// The paywall. Everything it claims is enforced in the services, so the
/// feature list is a description of behaviour, not a wish.
struct PremiumView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var pro: ProService { model.pro }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: ACTheme.Space.lg) {
                    crown
                        .staged()
                    benefits
                        .staged(0.06)
                    purchase
                        .staged(0.12)
                    finePrint
                        .staged(0.16)
                }
                .padding(ACTheme.Space.lg)
                .padding(.bottom, ACTheme.Space.xxl)
            }
            .background(CanvasBackground())
            .navigationTitle("AppCatcher Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ACTheme.Palette.textSecondary)
                            .padding(8)
                            .background(ACTheme.Palette.surfaceRaised, in: Circle())
                    }
                }
            }
        }
    }

    // MARK: Crown

    private var crown: some View {
        VStack(spacing: ACTheme.Space.md) {
            ZStack {
                Circle()
                    .fill(ACTheme.Gradients.premium)
                    .frame(width: 92, height: 92)
                    .opacity(0.18)
                Circle()
                    .strokeBorder(ACTheme.Gradients.premium, lineWidth: 1.5)
                    .frame(width: 68, height: 68)
                Image(systemName: pro.isPro ? "checkmark.seal.fill" : "crown.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(ACTheme.Gradients.premium)
            }
            VStack(spacing: 6) {
                Text(pro.isPro ? "You're on Pro" : "Everything the cleaner won't do for free")
                    .font(ACType.title)
                    .foregroundStyle(ACTheme.Palette.text)
                    .multilineTextAlignment(.center)
                Text(pro.isPro
                     ? "Unlimited history, encryption and the schedule are unlocked on this Apple Account."
                     : "One purchase, stays with the app. No subscription, no telemetry, no cloud account.")
                    .font(ACType.body)
                    .foregroundStyle(ACTheme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, ACTheme.Space.sm)
    }

    // MARK: Benefits

    private var benefits: some View {
        Card {
            VStack(alignment: .leading, spacing: ACTheme.Space.md) {
                Text("What unlocks").eyebrow()
                benefit("infinity", "Unlimited backup history", "Keep every version instead of the newest one.")
                benefit("lock.fill", "AES-256 encrypted archives", "Your password stretches into the key. We can't read your files.")
                benefit("clock.arrow.circlepath", "Scheduled cleaning", "Caches, temp and logs swept on a cadence you set.")
                benefit("globe", "Web data sweep", "WebView storage and URLSession blobs, the part that quietly grows.")
                benefit("checkmark.seal.fill", "Integrity verification", "Re-hash every stored file and prove a backup opens.")
            }
        }
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: ACTheme.Space.md) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ACTheme.Gradients.premium)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(ACType.row).foregroundStyle(ACTheme.Palette.text)
                Text(detail).font(ACType.caption).foregroundStyle(ACTheme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Purchase

    private var purchase: some View {
        VStack(spacing: ACTheme.Space.sm) {
            if pro.isPro {
                Card(tint: ACTheme.Palette.gold) {
                    VStack(alignment: .leading, spacing: ACTheme.Space.sm) {
                        Label("Pro is active", systemImage: "crown.fill")
                            .font(ACType.headline)
                            .foregroundStyle(ACTheme.Palette.gold)
                        Text("Purchases are tied to the Apple Account that bought them. Restoring re-links them on this device.")
                            .font(ACType.caption)
                            .foregroundStyle(ACTheme.Palette.textTertiary)
                        ActionButton(
                            title: "Restore purchases",
                            systemImage: "arrow.clockwise",
                            tone: .ghost,
                            isBusy: pro.status == .purchasing
                        ) {
                            Task { await pro.restore() }
                        }
                        if pro.offersPreviewUnlock {
                            // A local build cannot prove the purchase, so it must
                            // also be able to take the preview unlock back.
                            Button("Lock Pro again") { pro.lockAgain() }
                                .font(ACType.caption)
                                .foregroundStyle(ACTheme.Palette.textTertiary)
                        }
                    }
                }
            } else {
                priceRow
                ActionButton(
                    title: purchaseTitle,
                    systemImage: "crown.fill",
                    tone: .premium,
                    isBusy: pro.status == .purchasing || pro.status == .loading
                ) {
                    Task {
                        if pro.offersPreviewUnlock {
                            pro.unlockForPreview()
                        } else {
                            await pro.purchase()
                        }
                    }
                }
                Button("Restore previous purchase") {
                    Task { await pro.restore() }
                }
                .font(ACType.caption)
                .foregroundStyle(ACTheme.Palette.textSecondary)
            }

            if case .failed(let message) = pro.status {
                Text(message)
                    .font(ACType.caption)
                    .foregroundStyle(ACTheme.Palette.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var priceRow: some View {
        Card {
            HStack(alignment: .center, spacing: ACTheme.Space.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AppCatcher Pro").font(ACType.row)
                    Text("One-time · this device family")
                        .font(ACType.caption)
                        .foregroundStyle(ACTheme.Palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(priceText)
                        .font(ACType.headline)
                        .foregroundStyle(ACTheme.Gradients.premium)
                        .monospacedDigit()
                    if pro.product == nil {
                        Text(pro.isChecking ? "Contacting App Store…" : "Not on the App Store yet")
                            .font(ACType.micro)
                            .foregroundStyle(ACTheme.Palette.textTertiary)
                    }
                }
            }
        }
    }

    private var priceText: String {
        guard let product = pro.product else { return "$4.99" }
        return product.displayPrice
    }

    private var purchaseTitle: String {
        if pro.status == .purchasing { return "Completing purchase" }
        if pro.offersPreviewUnlock { return "Unlock Pro on this build" }
        return "Unlock Pro · \(priceText)"
    }

    private var finePrint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How the free version works").eyebrow()
            Text("Free keeps the daily loop: scan, see exactly what is taking space, clear it, and seal one backup you can verify and restore. Pro adds history, encryption and the schedule — it never adds ads or accounts.")
                .font(ACType.caption)
                .foregroundStyle(ACTheme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if pro.storeIsUnavailable {
                Text("This build could not fetch a StoreKit product, so the unlock button opens Pro locally instead of charging you. Live builds use the App Store.")
                    .font(ACType.caption)
                    .foregroundStyle(ACTheme.Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
