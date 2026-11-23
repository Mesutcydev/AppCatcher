import SwiftUI

/// The detailed list: every group, every folder inside it, and exactly what a
/// tap will remove.
struct CleanerView: View {
    @Environment(AppModel.self) private var model

    @State private var confirmation: Set<CacheKind>?
    @State private var revealed: Set<CacheKind> = []

    private var cache: CacheService { model.cache }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ACTheme.Space.md) {
                    summary
                    if cache.groups.isEmpty {
                        Card {
                            EmptyState(
                                systemImage: cache.hasScanned ? "checkmark.seal" : "magnifyingglass",
                                title: cache.hasScanned ? "No removable files" : "Not scanned yet",
                                message: cache.hasScanned
                                    ? "This container is already lean. New junk appears the moment you use the app again."
                                    : "AppCatcher walks the sandbox to find caches, temp files and WebView storage.",
                                action: { Task { await model.rescan() } },
                                actionTitle: "Scan container"
                            )
                        }
                    } else {
                        ForEach(cache.groups) { group in
                            groupCard(group)
                        }
                    }
                }
                .padding(.horizontal, ACTheme.Space.lg)
                .padding(.bottom, 110)
            }
            .background(CanvasBackground())
            .navigationTitle("Cleaner")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await model.rescan() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.rescan() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(cache.isBusy)
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .confirmationDialog(
                "Clear \(ByteFormat.string(pendingBytes))?",
                isPresented: Binding(
                    get: { confirmation != nil },
                    set: { if !$0 { confirmation = nil } }
                ),
                titleVisibility: .visible,
                presenting: confirmation
            ) { kinds in
                Button("Clear \(kinds.count) group\(kinds.count == 1 ? "" : "s")", role: .destructive) {
                    let chosen = kinds
                    confirmation = nil
                    Task { await model.runClean(kinds: chosen) }
                }
                Button("Cancel", role: .cancel) { confirmation = nil }
            } message: { _ in
                Text("Caches rebuild themselves. Sensitive groups can sign you out of embedded web sessions.")
            }
        }
    }

    // MARK: Header

    private var summary: some View {
        Card(tint: ACTheme.Palette.mint) {
            HStack(alignment: .center, spacing: ACTheme.Space.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected").eyebrow()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(ByteFormat.value(cache.selectedBytes))
                            .font(ACType.heroSmall)
                            .contentTransition(.numericText())
                        Text(ByteFormat.unit(cache.selectedBytes))
                            .font(ACType.footnote)
                            .foregroundStyle(ACTheme.Palette.textSecondary)
                    }
                    .foregroundStyle(ACTheme.Palette.text)
                    Text(selectionSummary)
                        .font(ACType.caption)
                        .foregroundStyle(ACTheme.Palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Button(cache.isAllSelected ? "Deselect all" : "Select all") {
                        toggleAll()
                    }
                    .font(ACType.footnote)
                    .foregroundStyle(ACTheme.Palette.aqua)
                    Text("\(cache.groups.count) groups · \(itemCount) folders")
                        .font(ACType.caption)
                        .foregroundStyle(ACTheme.Palette.textTertiary)
                }
            }
        }
    }

    private var selectionSummary: String {
        if cache.selection.isEmpty { return "Nothing selected" }
        return cache.selection
            .sorted { $0.rawValue < $1.rawValue }
            .map { $0.title }
            .joined(separator: " · ")
    }

    private var itemCount: Int { cache.groups.reduce(0) { $0 + $1.itemCount } }

    private var pendingBytes: Int64 { cache.selectedBytes }

    private func toggleAll() {
        Haptics.select()
        cache.selection = cache.isAllSelected ? [] : Set(cache.groups.map(\.kind))
    }

    // MARK: Group card

    private func groupCard(_ group: CacheGroup) -> some View {
        let isOn = Binding(
            get: { cache.selection.contains(group.kind) },
            set: { on in
                if on { cache.selection.insert(group.kind) } else { cache.selection.remove(group.kind) }
            }
        )
        return VStack(alignment: .leading, spacing: 0) {
            DataRow(
                title: group.kind.title,
                subtitle: group.kind.blurb,
                amount: ByteFormat.string(group.bytes),
                systemImage: group.kind.symbol,
                tint: group.kind.isSensitive ? ACTheme.Palette.amber : ACTheme.Palette.mint,
                isOn: isOn
            )

            if group.kind.isSensitive {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text("Can end embedded web sessions and cached offline pages")
                        .font(ACType.caption)
                }
                .foregroundStyle(ACTheme.Palette.amber)
                .padding(.top, ACTheme.Space.xs)
            }

            Button {
                withAnimation(ACTheme.Motion.standard) {
                    if revealed.contains(group.kind) { revealed.remove(group.kind) }
                    else { revealed.insert(group.kind) }
                }
                Haptics.select()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: revealed.contains(group.kind) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(group.itemCount) folder\(group.itemCount == 1 ? "" : "s")")
                        .font(ACType.caption)
                    Spacer()
                }
                .foregroundStyle(ACTheme.Palette.textTertiary)
                .padding(.top, ACTheme.Space.sm)
            }
            .buttonStyle(.plain)

            if revealed.contains(group.kind) {
                VStack(spacing: 0) {
                    ForEach(group.items.prefix(12)) { item in
                        HStack(spacing: ACTheme.Space.sm) {
                            Image(systemName: item.isProtected ? "lock.fill" : "folder.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(item.isProtected ? ACTheme.Palette.textTertiary : ACTheme.Palette.aqua)
                                .frame(width: 16)
                            Text(item.title)
                                .font(ACType.caption)
                                .foregroundStyle(ACTheme.Palette.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text(ByteFormat.string(item.bytes))
                                .font(ACType.caption)
                                .monospacedDigit()
                                .foregroundStyle(ACTheme.Palette.textTertiary)
                        }
                        .padding(.vertical, 6)
                        .padding(.leading, 2)
                        Divider().overlay(ACTheme.Palette.hairline)
                    }
                    if group.items.count > 12 {
                        Text("+\(group.items.count - 12) more")
                            .font(ACType.caption)
                            .foregroundStyle(ACTheme.Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(ACTheme.Space.md)
        .background(ACTheme.Palette.surface, in: RoundedRectangle(cornerRadius: ACTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ACTheme.Radius.md, style: .continuous)
                .strokeBorder(isOn.wrappedValue ? ACTheme.Palette.mint.opacity(0.35) : ACTheme.Palette.hairline, lineWidth: 1)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: ACTheme.Space.sm) {
            if cache.isBusy {
                FlowBar(progress: 0, indeterminate: true)
                    .padding(.horizontal, ACTheme.Space.xl)
            }
            ActionButton(
                title: cache.selection.isEmpty
                    ? "Select something to clear"
                    : "Clear \(ByteFormat.string(cache.selectedBytes))",
                systemImage: "sparkles",
                tone: cache.selection.isEmpty ? .ghost : .hero,
                isBusy: cache.isBusy,
                isDisabled: cache.selection.isEmpty
            ) {
                confirmation = cache.selection
            }
        }
        .padding(.horizontal, ACTheme.Space.lg)
        .padding(.top, ACTheme.Space.sm)
        .padding(.bottom, ACTheme.Space.sm)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider().overlay(ACTheme.Palette.hairline)
        }
    }
}

extension CacheService {
    var isAllSelected: Bool {
        !groups.isEmpty && groups.allSatisfy { selection.contains($0.kind) }
    }
}
