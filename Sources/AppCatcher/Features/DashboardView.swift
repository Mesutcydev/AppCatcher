import SwiftUI

/// Home screen: what is taking space, what AppCatcher can win back, and the
/// one tap that does it.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cleaning = false
    @State private var burst = false

    private var cache: CacheService { model.cache }
    private var snapshot: StorageSnapshot { cache.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ACTheme.Space.lg) {
                    hero
                        .staged()
                    breakdown
                        .staged(0.05)
                    quickActions
                        .staged(0.1)
                    recent
                        .staged(0.15)
                    sandboxNote
                        .staged(0.2)
                }
                .padding(.horizontal, ACTheme.Space.lg)
                .padding(.bottom, ACTheme.Space.xxl)
            }
            .background(CanvasBackground())
            .navigationTitle("AppCatcher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.pro.isPro {
                        ProBadge()
                    } else {
                        Button {
                            Haptics.tap()
                            model.showingPaywall = true
                        } label: {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(ACTheme.Palette.gold)
                        }
                    }
                }
            }
            .refreshable { await model.rescan() }
            .task {
                if !cache.hasScanned { await model.rescan() }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: ACTheme.Space.lg) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reclaimable now").eyebrow()
                        Text(headline)
                            .font(ACType.title)
                            .foregroundStyle(ACTheme.Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if cache.isBusy {
                        FlowBar(progress: 0)
                            .frame(width: 60)
                    }
                }

                HStack(spacing: ACTheme.Space.lg) {
                    MetricGauge(
                        progress: gaugeProgress,
                        value: ByteFormat.value(cache.removable),
                        unit: ByteFormat.unit(cache.removable),
                        caption: "in caches"
                    )

                    VStack(alignment: .leading, spacing: ACTheme.Space.sm) {
                        metric("Free on this iPhone", ByteFormat.string(snapshot.deviceFree), ACTheme.Palette.mint)
                        metric("Used by everything", ByteFormat.string(snapshot.deviceUsed), ACTheme.Palette.aqua)
                        metric("This app's container", ByteFormat.string(snapshot.containerTotal), ACTheme.Palette.violet)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                ActionButton(
                    title: primaryActionTitle,
                    systemImage: burst ? "checkmark.circle.fill" : "sparkles",
                    tone: burst ? .premium : .hero,
                    isBusy: cache.isBusy,
                    isDisabled: cache.removable == 0 && !burst,
                    action: primaryAction
                )
            }
        }
        .overlay {
            if burst {
                RoundedRectangle(cornerRadius: ACTheme.Radius.xl, style: .continuous)
                    .strokeBorder(ACTheme.Palette.mint.opacity(burst ? 0 : 0.7), lineWidth: 2)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.7)) { burst = false }
                    }
                    .allowsHitTesting(false)
            }
        }
    }

    private var headline: String {
        if cache.isBusy { return "Working…" }
        if burst { return "Container is spotless" }
        if cache.removable == 0 && cache.hasScanned { return "Nothing to clear" }
        return "\(ByteFormat.string(cache.removable)) of junk is sitting in here"
    }

    private var primaryActionTitle: String {
        if cache.isBusy { return "Scanning" }
        if cache.removable == 0 { return "All clear" }
        return "Clean \(ByteFormat.string(cache.removable))"
    }

    private var gaugeProgress: Double {
        ByteFormat.percent(snapshot.removable, of: max(snapshot.containerTotal, snapshot.removable))
    }

    private func metric(_ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: ACTheme.Space.sm) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label)
                .font(ACType.caption)
                .foregroundStyle(ACTheme.Palette.textTertiary)
            Spacer()
            Text(value)
                .font(ACType.footnote)
                .monospacedDigit()
                .foregroundStyle(ACTheme.Palette.text)
        }
    }

    private func primaryAction() {
        guard !cache.isBusy else { return }
        if cache.removable == 0 {
            Task { await model.rescan() }
            return
        }
        cleaning = true
        let kinds = Set(CacheKind.allCases.filter { kind in
            guard let group = cache.group(for: kind) else { return false }
            return group.bytes > 0 && !(kind == .web && !model.settings.autoCleanWebData)
        })
        Task {
            Haptics.scanComplete()
            let freed = await model.runClean(kinds: kinds)
            cleaning = false
            if freed > 0 {
                burst = true
                if !reduceMotion {
                    try? await Task.sleep(for: .milliseconds(1_400))
                    burst = false
                }
            }
        }
    }

    // MARK: Breakdown

    private var breakdown: some View {
        Card {
            VStack(alignment: .leading, spacing: ACTheme.Space.md) {
                SectionHeader(title: "Inside this container", detail: "last scan \(lastScanText)")
                UsageBar(segments: segments)
                    .frame(height: 14)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { _, segment in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(segment.color).frame(width: 10, height: 10)
                            Text(segment.label).font(ACType.caption).foregroundStyle(ACTheme.Palette.textSecondary)
                            Spacer()
                            Text(ByteFormat.string(segment.bytes))
                                .font(ACType.caption)
                                .monospacedDigit()
                                .foregroundStyle(ACTheme.Palette.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private var segments: [UsageBar.Segment] {
        var out: [UsageBar.Segment] = [
            .init(bytes: cache.group(for: .caches)?.bytes ?? 0, color: ACTheme.Palette.mint, label: "Caches"),
            .init(bytes: cache.group(for: .temp)?.bytes ?? 0, color: ACTheme.Palette.aqua, label: "Temp files"),
            .init(bytes: (cache.group(for: .web)?.bytes ?? 0) + (cache.group(for: .httpStorage)?.bytes ?? 0),
                  color: ACTheme.Palette.violet, label: "Web & network"),
            .init(bytes: snapshot.documents, color: ACTheme.Palette.amber, label: "Documents"),
            .init(bytes: max(snapshot.data - snapshot.documents, 0), color: ACTheme.Palette.textTertiary, label: "App data"),
        ]
        out.removeAll { $0.bytes <= 0 }
        if out.isEmpty {
            out = [.init(bytes: 1, color: ACTheme.Palette.hairline, label: "Empty container")]
        }
        return out
    }

    private var lastScanText: String {
        guard let date = cache.lastScan else { return "never" }
        return TimeFormat.ago(date)
    }

    // MARK: Quick actions

    private var quickActions: some View {
        VStack(spacing: ACTheme.Space.md) {
            NavigationLink {
                BackupsView()
            } label: {
                actionTile(
                    symbol: model.backups.latest == nil ? "lock.doc" : "checkmark.seal.fill",
                    title: model.backups.latest == nil ? "No backup yet" : "Last backup \(TimeFormat.ago(model.backups.latest!.createdAt))",
                    detail: model.backups.latest.map { "\(ByteFormat.string($0.originalBytes)) → \(ByteFormat.string($0.bytes)) sealed" }
                        ?? "Seal your documents into one encrypted file",
                    tint: ACTheme.Palette.aqua
                )
            }
            .buttonStyle(PressableStyle())

            NavigationLink {
                CleanerView()
            } label: {
                actionTile(
                    symbol: "list.bullet.rectangle.stack",
                    title: "Inspect before you delete",
                    detail: "\(cache.groups.count) groups · \(ByteFormat.string(cache.removable)) found",
                    tint: ACTheme.Palette.mint
                )
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func actionTile(symbol: String, title: String, detail: String, tint: Color) -> some View {
        HStack(spacing: ACTheme.Space.md) {
            IconBadge(systemImage: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(ACType.row).foregroundStyle(ACTheme.Palette.text)
                Text(detail).font(ACType.caption).foregroundStyle(ACTheme.Palette.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ACTheme.Palette.textTertiary)
        }
        .padding(ACTheme.Space.md)
        .background(ACTheme.Palette.surface, in: RoundedRectangle(cornerRadius: ACTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ACTheme.Radius.md, style: .continuous)
                .strokeBorder(ACTheme.Palette.hairline, lineWidth: 1)
        }
    }

    // MARK: Recent

    @ViewBuilder
    private var recent: some View {
        if !model.activity.events.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: ACTheme.Space.md) {
                    SectionHeader(title: "Recent activity")
                    ForEach(model.activity.events.prefix(4)) { event in
                        HStack(spacing: ACTheme.Space.sm) {
                            Image(systemName: event.kind.symbol)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(ACTheme.Palette.aqua)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).font(ACType.footnote).foregroundStyle(ACTheme.Palette.text)
                                Text(event.detail).font(ACType.caption).foregroundStyle(ACTheme.Palette.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(TimeFormat.ago(event.date))
                                .font(ACType.caption)
                                .foregroundStyle(ACTheme.Palette.textTertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var sandboxNote: some View {
        HStack(alignment: .top, spacing: ACTheme.Space.sm) {
            Image(systemName: "lock.shield")
                .font(.system(size: 13))
                .foregroundStyle(ACTheme.Palette.textTertiary)
            Text("iOS sandboxes every app, so AppCatcher can only see and clear files this container owns. Other apps' caches are cleaned by iOS itself — offload them in Settings › General › iPhone Storage.")
                .font(ACType.caption)
                .foregroundStyle(ACTheme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ACTheme.Space.md)
        .background(ACTheme.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: ACTheme.Radius.sm, style: .continuous))
    }
}
