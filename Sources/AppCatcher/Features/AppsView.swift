import SwiftUI

/// Read-only inventory of what is installed on the device.
///
/// The data comes from private APIs (LSApplicationWorkspace, with a
/// MobileInstallation fallback), so this tab is for personally sideloaded
/// builds only and must be removed for any store submission.
struct AppsView: View {
    @Environment(AppModel.self) private var model

    private var service: InstalledAppsService { model.apps }

    var body: some View {
        NavigationStack {
            Group {
                if service.unavailable {
                    ScrollView {
                        VStack(spacing: ACTheme.Space.md) {
                            Card {
                                EmptyState(
                                    systemImage: "eye.slash",
                                    title: "iOS blocked the app list",
                                    message: "On this iOS version the app-list APIs need entitlements a normal signed app does not carry. The lines below say exactly which layer failed."
                                )
                            }
                            Card(tint: ACTheme.Palette.amber) {
                                VStack(alignment: .leading, spacing: ACTheme.Space.sm) {
                                    Text("Diagnostics").eyebrow()
                                    ForEach(Array(service.diagnostics.rows.enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(ACTheme.Palette.textSecondary)
                                    }
                                }
                            }
                            Card(tint: ACTheme.Palette.aqua) {
                                VStack(alignment: .leading, spacing: ACTheme.Space.sm) {
                                    Text("Why it is blocked").eyebrow()
                                    Text("On iOS 18 and later, Apple gates the entire installed-app list behind entitlements that only Apple-signed profiles can carry. A personal development certificate cannot hold them, no matter what a resign tool injects — iOS checks the Apple-signed provisioning profile, not the code signature.")
                                        .font(ACType.caption)
                                        .foregroundStyle(ACTheme.Palette.textTertiary)
                                    Text("There is no signed-app API left that lists every app. The inventory only exists on the Apple side (Settings, MDM) or on a trusted computer the phone has been paired to.")
                                        .font(ACType.caption)
                                        .foregroundStyle(ACTheme.Palette.textTertiary)
                                }
                            }
                        }
                        .padding(ACTheme.Space.lg)
                    }
                } else {
                    list
                }
            }
            .background(CanvasBackground())
            .navigationTitle("Apps")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: Bindable(service).searchText, prompt: Text("Name or bundle id"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        service.includeSystem.toggle()
                        Haptics.select()
                    } label: {
                        Image(systemName: service.includeSystem ? "gearshape.2.fill" : "gearshape.2")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { _ = await service.syncRemote() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(service.syncSource.isEmpty)
                }
            }
            .task { await service.load() }
            .refreshable { _ = await service.syncRemote() }
        }
    }

    private var list: some View {
        List {
            Section {
                HStack(spacing: ACTheme.Space.md) {
                    IconBadge(systemImage: "square.grid.2x2", tint: ACTheme.Palette.violet, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(service.userCount) user apps")
                            .font(ACType.row)
                            .foregroundStyle(ACTheme.Palette.text)
                        Text("\(ByteFormat.string(service.userBytes)) of app data on this iPhone")
                            .font(ACType.caption)
                            .foregroundStyle(ACTheme.Palette.textTertiary)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)

                if !service.syncSource.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: service.syncSource == "device" ? "iphone" : "desktopcomputer")
                            .font(.system(size: 11))
                            .foregroundStyle(ACTheme.Palette.mint)
                        Text(syncCaption)
                            .font(ACType.caption)
                            .foregroundStyle(ACTheme.Palette.textTertiary)
                        Spacer()
                    }
                    .padding(.top, 4)
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                ForEach(service.visible) { item in
                    AppRow(item: item)
                        .listRowBackground(ACTheme.Palette.surface.opacity(0.6))
                }
            } header: {
                Text(service.includeSystem ? "All apps" : "User apps").eyebrow()
            } footer: {
                Text("Read-only. iOS gives no app the power to read or clear another app's files, so the only lever per app is Settings › General › iPhone Storage (Offload or Delete). Sizes are what the system reports for each bundle.\(syncHint)")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var syncCaption: String {
        var base = "Synced from your computer"
        if let date = service.syncedAt { base += " · \(TimeFormat.ago(date))" }
        return base
    }

    private var syncHint: String {
        guard service.syncSource == "device" else {
            return " \nPull to refresh, or tap ↻, when the iPhone is plugged into the computer the inventory is generated there and synced here."
        }
        return ""
    }
}

private struct AppRow: View {
    let item: InstalledAppsService.Item

    var body: some View {
        HStack(spacing: ACTheme.Space.md) {
            monogram
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(ACType.row)
                    .foregroundStyle(ACTheme.Palette.text)
                    .lineLimit(1)
                Text(item.bundleID)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(ACTheme.Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: ACTheme.Space.sm)
            VStack(alignment: .trailing, spacing: 4) {
                Text(ByteFormat.string(item.totalBytes))
                    .font(ACType.footnote)
                    .monospacedDigit()
                    .foregroundStyle(ACTheme.Palette.textSecondary)
                HStack(spacing: 4) {
                    if item.kind != .user {
                        Chip(text: item.kind.rawValue, tint: ACTheme.Palette.textTertiary)
                    }
                    Text("v\(item.version)")
                        .font(ACType.caption)
                        .foregroundStyle(ACTheme.Palette.textTertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// No app icons are reachable without more private API, so rows carry a
    /// stable monogram whose hue is derived from the bundle id.
    private var monogram: some View {
        let hue = Double(abs(item.bundleID.hashValue) % 360) / 360
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hue: hue, saturation: 0.55, brightness: 0.85).opacity(0.18))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(hue: hue, saturation: 0.55, brightness: 0.85).opacity(0.35), lineWidth: 1)
            Text(String(item.name.prefix(1)).uppercased())
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hue: hue, saturation: 0.5, brightness: 0.95))
        }
        .frame(width: 38, height: 38)
    }
}
