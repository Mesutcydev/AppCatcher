import SwiftUI

/// Controls, numbers, and the honest explanation of what an iOS app is
/// allowed to delete.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                proSection

                Section {
                    LockedToggle(
                        title: "Automatic cleaning",
                        isOn: $settings.autoCleanEnabled,
                        isLocked: !model.pro.isPro
                    ) {
                        Haptics.warning()
                        model.showingPaywall = true
                    }
                    if settings.autoCleanEnabled {
                        Picker("Cadence", selection: $settings.autoCleanInterval) {
                            ForEach(AppSettings.AutoCleanInterval.allCases) { interval in
                                Text(interval.label).tag(interval)
                            }
                        }
                    }
                    LockedToggle(
                        title: "Include web data",
                        isOn: $settings.autoCleanWebData,
                        isLocked: !model.pro.isPro
                    ) {
                        Haptics.warning()
                        model.showingPaywall = true
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text(nextRunText)
                }

                Section {
                    Toggle("Back up caches too", isOn: $settings.includeCachesInBackups)
                    Toggle("Ask before restoring", isOn: $settings.confirmBeforeRestore)
                    LabeledContent("Archives kept", value: "\(model.backups.records.count)")
                    LabeledContent("Vault size", value: ByteFormat.string(model.backups.totalBytes))
                    LabeledContent("Guarded copies", value: ByteFormat.string(model.backups.restoreGuardBytes))
                    if model.backups.restoreGuardBytes > 0 {
                        Button("Delete guarded copies", role: .destructive) {
                            model.backups.clearRestoreGuards()
                            Haptics.tap()
                            model.toast = "Guarded copies removed"
                        }
                    }
                } header: {
                    Text("Backups")
                } footer: {
                    Text("A guarded copy is what was in Documents right before a restore. Delete it once you are sure the restore was right.")
                }

                Section {
                    row("App caches", model.cache.group(for: .caches)?.bytes ?? 0, ACTheme.Palette.mint)
                    row("Temporary", model.cache.group(for: .temp)?.bytes ?? 0, ACTheme.Palette.aqua)
                    row("Web & network",
                        (model.cache.group(for: .web)?.bytes ?? 0) + (model.cache.group(for: .httpStorage)?.bytes ?? 0),
                        ACTheme.Palette.violet)
                    row("Logs", model.cache.group(for: .logs)?.bytes ?? 0, ACTheme.Palette.textTertiary)
                    row("Documents", model.cache.snapshot.documents, ACTheme.Palette.amber)
                    row("App data", model.cache.snapshot.data, ACTheme.Palette.gold)
                    LabeledContent("Lifetime reclaimed", value: ByteFormat.string(model.settings.lifetimeReclaimed))
                } header: {
                    Text("Container")
                } footer: {
                    Text("Measured from this app's own sandbox. Total free space on the device is \(ByteFormat.string(model.cache.snapshot.deviceFree)) of \(ByteFormat.string(model.cache.snapshot.deviceTotal)).")
                }

                Section {
                    Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
                    Button("Reset activity log", role: .destructive) {
                        model.activity.clear()
                        Haptics.tap()
                    }
                } header: {
                    Text("General")
                }

                Section {
                    LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
                    LabeledContent("Archive format", value: "ACBA v\(CatcherArchive.version)")
                    NavigationLink {
                        SandboxExplainer()
                    } label: {
                        Text("Why only this app's files")
                    }
                } header: {
                    Text("About")
                }
            }
            .scrollContentBackground(.hidden)
            .background(CanvasBackground())
            .onChange(of: settings.hapticsEnabled) { _, enabled in Haptics.isEnabled = enabled }
            .navigationTitle("Settings")
            .refreshable { await model.rescan() }
        }
    }

    private var proSection: some View {
        Section {
            NavigationLink {
                PremiumView()
            } label: {
                HStack(spacing: ACTheme.Space.md) {
                    IconBadge(systemImage: "crown.fill", tint: ACTheme.Palette.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.pro.isPro ? "AppCatcher Pro · Active" : "AppCatcher Pro")
                            .font(ACType.row)
                        Text(model.pro.isPro
                             ? "History, encryption and schedule unlocked"
                             : "Unlimited history, encrypted archives, scheduled cleans")
                            .font(ACType.caption)
                            .foregroundStyle(ACTheme.Palette.textTertiary)
                    }
                }
            }
        }
    }

    private var nextRunText: String {
        guard model.settings.autoCleanEnabled else {
            return "iOS only wakes apps that hold a background entitlement. AppCatcher does not, so a scheduled clean runs the next time you open the app."
        }
        guard let next = model.settings.nextAutoCleanDate else { return "" }
        return "Next run \(TimeFormat.ago(next)) — when the app is opened. Background wake-ups need an entitlement this build does not carry."
    }

    private func row(_ label: String, _ bytes: Int64, _ tint: Color) -> some View {
        HStack {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(label)
            Spacer()
            Text(ByteFormat.string(bytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// A switch that is a paywall moment, not a bug.
private struct LockedToggle: View {
    let title: String
    @Binding var isOn: Bool
    let isLocked: Bool
    let onLockedTap: () -> Void

    var body: some View {
        if isLocked {
            Button(action: onLockedTap) {
                HStack {
                    Text(title)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ACTheme.Palette.gold)
                    Toggle(title, isOn: .constant(false))
                        .labelsHidden()
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Toggle(title, isOn: $isOn)
        }
    }
}

private struct SandboxExplainer: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ACTheme.Space.md) {
                Card {
                    VStack(alignment: .leading, spacing: ACTheme.Space.sm) {
                        Text("What iOS allows").eyebrow()
                        paragraph("Every app lives in its own container. AppCatcher can read, measure and delete anything inside its container: caches, temporary files, URLSession storage, WebView data, logs, Documents and Application Support.")
                        paragraph("It cannot see inside another app's container. That is not an AppCatcher limitation — it is the sandbox, and no App Store app can bypass it.")
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: ACTheme.Space.sm) {
                        Text("Where the big numbers live instead").eyebrow()
                        bullet("Settings › General › iPhone Storage", "Shows per-app documents and data, and offers Offload or Delete.")
                        bullet("Offload an app", "Removes the binary but keeps its data; the caches go with it.")
                        bullet("Safari", "Settings › Apps › Safari › Clear History and Website Data.")
                        bullet("Reboot", "iOS clears a class of system caches on its own during boot.")
                    }
                }
                Card(tint: ACTheme.Palette.aqua) {
                    VStack(alignment: .leading, spacing: ACTheme.Space.sm) {
                        Text("What AppCatcher is genuinely good at").eyebrow()
                        paragraph("Power users who export files, recordings or caches out of this container through the Files app, and anyone who wants a verified, restorable snapshot of their work before trying something risky.")
                    }
                }
            }
            .padding(ACTheme.Space.lg)
        }
        .background(CanvasBackground())
        .navigationTitle("The sandbox")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(ACType.body)
            .foregroundStyle(ACTheme.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(ACType.footnote).foregroundStyle(ACTheme.Palette.text)
            Text(detail).font(ACType.caption).foregroundStyle(ACTheme.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
