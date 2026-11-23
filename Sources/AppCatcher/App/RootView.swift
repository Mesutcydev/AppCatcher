import SwiftUI

/// Tab shell, global toast, paywall and first-run story.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.route) {
            DashboardView()
                .tabItem { Label("Overview", systemImage: "sparkles") }
                .tag(AppModel.Tab.dashboard)

            CleanerView()
                .tabItem { Label("Cleaner", systemImage: "square.3.layers.3d.down.right") }
                .tag(AppModel.Tab.cleaner)

            BackupsView()
                .tabItem { Label("Backups", systemImage: "lock.doc") }
                .tag(AppModel.Tab.backups)

            // The installed-app inventory rides on a private framework. This is
            // a personal, sideload-only build, so the tab is unconditional;
            // a store submission must delete AppsView and the service instead.
            AppsView()
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
                .tag(AppModel.Tab.apps)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppModel.Tab.settings)
        }
        .tint(ACTheme.Palette.mint)
        .task { await model.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            model.cache.refreshVolume()
            Task { await model.autoCleanIfNeeded() }
        }
        .overlay(alignment: .top) { toast }
        .sheet(isPresented: $model.showingPaywall) { PremiumView() }
        .fullScreenCover(isPresented: firstRunBinding) { OnboardingView() }
    }

    private var firstRunBinding: Binding<Bool> {
        Binding(
            get: { !model.settings.hasCompletedOnboarding },
            set: { model.settings.hasCompletedOnboarding = !$0 }
        )
    }

    @ViewBuilder
    private var toast: some View {
        if let text = model.toast {
            ToastBar(text: text)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: text) {
                    try? await Task.sleep(for: .seconds(2.6))
                    withAnimation(ACTheme.Motion.quick) { model.toast = nil }
                }
                .allowsHitTesting(false)
        }
    }
}

/// Three screens that set expectations instead of selling a fantasy.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    private var pages: [Page] {
        [
            Page(
                symbol: "internaldrive",
                tint: ACTheme.Palette.aqua,
                title: "See where it all went",
                body: "AppCatcher measures your container file by file — caches, temp files, WebView storage, logs — and shows you the receipts before touching anything."
            ),
            Page(
                symbol: "lock.doc",
                tint: ACTheme.Palette.mint,
                title: "Seal it, then clean it",
                body: "Back up Documents and app data into one archive, optionally locked with AES-256. Verify any archive later, restore it in a tap, and keep a guarded copy of whatever was there before."
            ),
            Page(
                symbol: "lock.shield",
                tint: ACTheme.Palette.violet,
                title: "Honest about iOS",
                body: "The sandbox means no app can delete another app's caches. AppCatcher cleans what it owns, and points you at iPhone Storage for the rest."
            ),
        ]
    }

    @State private var index = 0

    var body: some View {
        VStack(spacing: ACTheme.Space.xl) {
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.offset) { position, page in
                    VStack(spacing: ACTheme.Space.lg) {
                        Spacer()
                        ZStack {
                            Circle().fill(page.tint.opacity(0.14)).frame(width: 148, height: 148)
                            Circle().strokeBorder(page.tint.opacity(0.35), lineWidth: 1).frame(width: 108, height: 108)
                            Image(systemName: page.symbol)
                                .font(.system(size: 44, weight: .medium))
                                .foregroundStyle(page.tint)
                        }
                        Text(page.title)
                            .font(ACType.title)
                            .foregroundStyle(ACTheme.Palette.text)
                            .multilineTextAlignment(.center)
                        Text(page.body)
                            .font(ACType.body)
                            .foregroundStyle(ACTheme.Palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, ACTheme.Space.xl)
                        Spacer()
                    }
                    .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            ActionButton(
                title: index == pages.count - 1 ? "Open AppCatcher" : "Continue",
                systemImage: index == pages.count - 1 ? "arrow.right.circle.fill" : nil,
                action: advance
            )
            .padding(.horizontal, ACTheme.Space.lg)

            Button("Skip tour") { finish() }
                .font(ACType.caption)
                .foregroundStyle(ACTheme.Palette.textTertiary)
                .padding(.bottom, ACTheme.Space.lg)
        }
        .background(CanvasBackground())
    }

    private func advance() {
        Haptics.tap()
        if index < pages.count - 1 {
            withAnimation(ACTheme.Motion.standard) { index += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        model.settings.hasCompletedOnboarding = true
        Task { await model.rescan() }
    }
}

private struct Page {
    var symbol: String
    var tint: Color
    var title: String
    var body: String
}
