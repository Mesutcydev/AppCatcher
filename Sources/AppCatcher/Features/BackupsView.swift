import SwiftUI
import UniformTypeIdentifiers

/// Backups: seal the container into one verifiable file, keep history, restore
/// it later, move archives in and out with the Files app.
struct BackupsView: View {
    @Environment(AppModel.self) private var model

    @State private var showCreate = false
    @State private var showImport = false
    @State private var detail: BackupRecord?
    @State private var verifyReport: VerifyReport?

    private var backups: BackupService { model.backups }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ACTheme.Space.md) {
                    header
                        .staged()
                    archiveList
                        .staged(0.06)
                    howItWorks
                        .staged(0.12)
                }
                .padding(.horizontal, ACTheme.Space.lg)
                .padding(.bottom, 110)
            }
            .background(CanvasBackground())
            .navigationTitle("Backups")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { createBar }
            .sheet(isPresented: $showCreate) { NewBackupSheet() }
            .sheet(item: $detail) { record in
                BackupDetailSheet(record: record)
            }
            .sheet(item: $verifyReport) { report in
                VerifyReportSheet(report: report)
            }
            .fileImporter(
                isPresented: $showImport,
                allowedContentTypes: [.catcherArchive, .data, .item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { model.importBackup(from: url) }
                case .failure(let error):
                    model.toast = "Could not open that file: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        Card {
            VStack(alignment: .leading, spacing: ACTheme.Space.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Backup vault").eyebrow()
                        Text(backups.records.isEmpty
                             ? "Nothing sealed yet"
                             : "\(backups.records.count) archive\(backups.records.count == 1 ? "" : "s")")
                            .font(ACType.headline)
                            .foregroundStyle(ACTheme.Palette.text)
                    }
                    Spacer()
                    if !model.pro.isPro {
                        Button("Pro history") {
                            Haptics.tap()
                            model.showingPaywall = true
                        }
                        .font(ACType.caption)
                        .foregroundStyle(ACTheme.Palette.gold)
                    }
                }

                HStack(spacing: ACTheme.Space.lg) {
                    stat("On disk", ByteFormat.string(backups.totalBytes))
                    stat("Source", ByteFormat.string(backups.latest?.originalBytes ?? 0))
                    stat("Ratio", backups.latest.map { String(format: "%.0f%%", $0.ratio * 100) } ?? "—")
                }

                if !model.pro.isPro {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill").font(.system(size: 10))
                        Text("Free keeps one archive at a time. Pro keeps every version, plus password encryption.")
                            .font(ACType.caption)
                    }
                    .foregroundStyle(ACTheme.Palette.gold.opacity(0.9))
                    .padding(10)
                    .background(ACTheme.Palette.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: ACTheme.Radius.sm, style: .continuous))
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(ACType.row)
                .monospacedDigit()
                .foregroundStyle(ACTheme.Palette.text)
            Text(label).eyebrow()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: List

    @ViewBuilder
    private var archiveList: some View {
        if backups.records.isEmpty {
            Card {
                EmptyState(
                    systemImage: "arrow.down.doc",
                    title: "No archives",
                    message: "Your documents are only as safe as the last copy you made of them.",
                    action: { showCreate = true },
                    actionTitle: "Back up now"
                )
            }
        } else {
            ForEach(backups.records) { record in
                BackupRow(record: record) { detail = record }
            }
        }
    }

    // MARK: Explainer

    private var howItWorks: some View {
        Card {
            VStack(alignment: .leading, spacing: ACTheme.Space.sm) {
                Text("What goes in an archive").eyebrow()
                bullet("Documents", "Everything you created, always included.")
                bullet("App data", "Preferences and support files in Application Support.")
                bullet("Caches", "Optional. Off by default: they rebuild themselves.")
                Divider().overlay(ACTheme.Palette.hairline)
                Text("Every file is LZFSE-compressed and hashed. Set a password and the payload is sealed with AES-256-GCM using a key stretched from it, so a copied `.catcher` file is useless without the phrase.")
                    .font(ACType.caption)
                    .foregroundStyle(ACTheme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bullet(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "smallcircle.filled.circle")
                .font(.system(size: 8))
                .foregroundStyle(ACTheme.Palette.aqua)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(ACType.footnote).foregroundStyle(ACTheme.Palette.text)
                Text(detail).font(ACType.caption).foregroundStyle(ACTheme.Palette.textTertiary)
            }
        }
    }

    private var createBar: some View {
        ActionButton(title: "New backup", systemImage: "lock.doc", isBusy: backups.isBusy) {
            showCreate = true
        }
        .padding(.horizontal, ACTheme.Space.lg)
        .padding(.vertical, ACTheme.Space.sm)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider().overlay(ACTheme.Palette.hairline) }
    }
}

// MARK: - Row

private struct BackupRow: View {
    let record: BackupRecord
    let open: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            open()
        }) {
            HStack(spacing: ACTheme.Space.md) {
                IconBadge(
                    systemImage: record.isEncrypted ? "lock.doc.fill" : "doc.zipper",
                    tint: record.isEncrypted ? ACTheme.Palette.gold : ACTheme.Palette.aqua
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.name).font(ACType.row).foregroundStyle(ACTheme.Palette.text)
                    HStack(spacing: 6) {
                        Text(TimeFormat.exact(record.createdAt))
                        Text("·")
                        Text("\(record.fileCount) files")
                    }
                    .font(ACType.caption)
                    .foregroundStyle(ACTheme.Palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(ByteFormat.string(record.bytes))
                        .font(ACType.footnote)
                        .monospacedDigit()
                        .foregroundStyle(ACTheme.Palette.text)
                    HStack(spacing: 4) {
                        if record.verifiedAt != nil {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(ACTheme.Palette.mint)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ACTheme.Palette.textTertiary)
                    }
                }
            }
            .padding(ACTheme.Space.md)
            .background(ACTheme.Palette.surface, in: RoundedRectangle(cornerRadius: ACTheme.Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ACTheme.Radius.md, style: .continuous)
                    .strokeBorder(ACTheme.Palette.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Create sheet

struct NewBackupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var note = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var includeCaches = false
    @State private var mismatch = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text(Date().shortStamp))
                        .textInputAutocapitalization(.never)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                    Toggle("Include caches", isOn: $includeCaches)
                } header: {
                    Text("Archive")
                } footer: {
                    Text("Documents and app data are always included. Caches rebuild themselves, so they are usually dead weight in a backup.")
                }

                Section {
                    SecureField("Password", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Repeat password", text: $confirm)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    HStack {
                        Text("Encryption")
                        Spacer()
                        ProBadge()
                    }
                } footer: {
                    Text(mismatch
                         ? "The two passwords do not match."
                         : "Leave empty for a plain archive. A forgotten password cannot be recovered — the key is derived from the phrase alone.")
                }
                .foregroundStyle(mismatch ? ACTheme.Palette.danger : ACTheme.Palette.text)

                Section {
                    LabeledContent("Source size", value: ByteFormat.string(estimatedSource))
                    LabeledContent("Archives kept", value: model.pro.isPro ? "Unlimited" : "1 (free)")
                } header: {
                    Text("Summary")
                }
            }
            .scrollContentBackground(.hidden)
            .background(CanvasBackground())
            .navigationTitle("New backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard password.isEmpty || password == confirm else {
                            mismatch = true
                            Haptics.warning()
                            return
                        }
                        mismatch = false
                        Task {
                            let record = await model.createBackup(
                                name: name,
                                note: note,
                                password: password.isEmpty ? nil : password,
                                includeCaches: includeCaches
                            )
                            if record != nil { dismiss() }
                        }
                    } label: {
                        if model.backups.isBusy {
                            ProgressView()
                        } else {
                            Text("Seal")
                        }
                    }
                    .disabled(model.backups.isBusy)
                }
            }
            .overlay {
                if model.backups.isBusy {
                    VStack(spacing: ACTheme.Space.md) {
                        ProgressView().controlSize(.large)
                        Text("Compressing and sealing…")
                            .font(ACType.caption)
                            .foregroundStyle(ACTheme.Palette.textSecondary)
                        FlowBar(progress: model.backups.progress)
                            .frame(width: 180)
                    }
                    .padding(ACTheme.Space.xl)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ACTheme.Radius.lg, style: .continuous))
                }
            }
        }
        .presentationDetents([.large])
    }

    private var estimatedSource: Int64 {
        var total = DeepSize.of(Sandbox.documents) + DeepSize.of(Sandbox.appSupport)
        if includeCaches { total += DeepSize.of(Sandbox.caches) }
        return total
    }
}

// MARK: - Detail sheet

struct BackupDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let record: BackupRecord
    @State private var password = ""
    @State private var askBeforeRestore = false
    @State private var report: VerifyReport?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ACTheme.Space.md) {
                    Card {
                        VStack(alignment: .leading, spacing: ACTheme.Space.sm) {
                            HStack(spacing: ACTheme.Space.md) {
                                IconBadge(
                                    systemImage: record.isEncrypted ? "lock.doc.fill" : "doc.zipper",
                                    tint: record.isEncrypted ? ACTheme.Palette.gold : ACTheme.Palette.aqua,
                                    size: 46
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.name).font(ACType.headline).foregroundStyle(ACTheme.Palette.text)
                                    Text(TimeFormat.exact(record.createdAt))
                                        .font(ACType.caption)
                                        .foregroundStyle(ACTheme.Palette.textTertiary)
                                }
                            }
                            if !record.note.isEmpty {
                                Text(record.note)
                                    .font(ACType.body)
                                    .foregroundStyle(ACTheme.Palette.textSecondary)
                            }
                            HStack(spacing: 6) {
                                Chip(text: ByteFormat.string(live.bytes), tint: ACTheme.Palette.aqua)
                                Chip(text: "\(live.fileCount) files", tint: ACTheme.Palette.mint)
                                if live.includesCaches { Chip(text: "with caches", tint: ACTheme.Palette.violet) }
                                if live.isEncrypted { Chip(text: "AES-256", tint: ACTheme.Palette.gold) }
                            }
                            .padding(.top, 2)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: ACTheme.Space.sm) {
                            Text("Contents").eyebrow()
                            line("Sealed size", ByteFormat.string(live.bytes))
                            line("Source size", ByteFormat.string(live.originalBytes))
                            line("Compression", String(format: "%.0f%% of source", live.ratio * 100))
                            line("Made by", "AppCatcher \(live.appVersion)")
                            line("Integrity", integrityText)
                        }
                    }

                    if record.isEncrypted {
                        Card(tint: ACTheme.Palette.gold) {
                            VStack(alignment: .leading, spacing: ACTheme.Space.sm) {
                                Text("Password").eyebrow()
                                SecureField("Enter the archive password", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                        }
                    }

                    VStack(spacing: ACTheme.Space.sm) {
                        ActionButton(
                            title: "Restore this backup",
                            systemImage: "arrow.uturn.backward.circle.fill",
                            isBusy: model.backups.phase == .restoring
                        ) {
                            beginRestore()
                        }
                        HStack(spacing: ACTheme.Space.sm) {
                            ActionButton(
                                title: "Verify",
                                systemImage: "checkmark.seal",
                                tone: .ghost,
                                isBusy: model.backups.phase == .verifying
                            ) {
                                Task {
                                    report = await model.verify(record, password: password.isEmpty ? nil : password)
                                }
                            }
                            ShareLink(
                                item: record.url,
                                preview: SharePreview(record.name, image: Image(systemName: "doc.zipper"))
                            ) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export")
                                }
                                .font(ACType.headline)
                                .foregroundStyle(ACTheme.Palette.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, ACTheme.Space.md + 2)
                                .background(ACTheme.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: ACTheme.Radius.md, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: ACTheme.Radius.md, style: .continuous)
                                        .strokeBorder(ACTheme.Palette.hairline, lineWidth: 1)
                                }
                            }
                        }
                        ActionButton(
                            title: "Delete archive",
                            systemImage: "trash",
                            tone: .danger
                        ) {
                            model.delete(record)
                            dismiss()
                        }
                    }

                    Text("Restoring writes the archive back over your current documents. AppCatcher moves what was there first into a guarded copy you can find in Settings.")
                        .font(ACType.caption)
                        .foregroundStyle(ACTheme.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(ACTheme.Space.lg)
            }
            .background(CanvasBackground())
            .navigationTitle("Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Restore \(ByteFormat.string(record.originalBytes))?",
                isPresented: $askBeforeRestore,
                titleVisibility: .visible
            ) {
                Button("Restore now", role: .destructive) { runRestore() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Files in Documents with the same names are replaced. The previous contents are kept as a guarded copy.")
            }
            .sheet(item: $report) { result in
                VerifyReportSheet(report: result)
            }
        }
    }

    /// The catalogue copy, so a successful verify shows up immediately.
    private var live: BackupRecord {
        model.backups.records.first { $0.id == record.id } ?? record
    }

    private var integrityText: String {
        guard let checked = live.verifiedAt else { return "Never checked" }
        return "Verified \(TimeFormat.ago(checked))"
    }

    private func beginRestore() {
        guard model.backups.phase == .idle else { return }
        if model.settings.confirmBeforeRestore {
            askBeforeRestore = true
        } else {
            runRestore()
        }
    }

    private func runRestore() {
        Task {
            await model.restore(record, password: password.isEmpty ? nil : password)
            dismiss()
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(ACType.caption).foregroundStyle(ACTheme.Palette.textTertiary)
            Spacer()
            Text(value).font(ACType.footnote).monospacedDigit().foregroundStyle(ACTheme.Palette.text)
        }
    }
}

// MARK: - Verify report

struct VerifyReportSheet: View {
    let report: VerifyReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ACTheme.Space.md) {
                HStack(spacing: ACTheme.Space.md) {
                    IconBadge(
                        systemImage: report.ok ? "checkmark.seal.fill" : "xmark.octagon.fill",
                        tint: report.ok ? ACTheme.Palette.mint : ACTheme.Palette.danger,
                        size: 46
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(report.ok ? "Archive is intact" : "Archive has damage")
                            .font(ACType.headline)
                        Text("\(TimeFormat.duration(report.seconds)) to read and hash \(report.header.fileCount) files")
                            .font(ACType.caption)
                            .foregroundStyle(ACTheme.Palette.textTertiary)
                    }
                }
                if !report.ok {
                    Card(tint: ACTheme.Palette.danger) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(report.failures.prefix(12), id: \.self) { path in
                                Text(path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(ACTheme.Palette.danger)
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(ACTheme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CanvasBackground())
            .navigationTitle("Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Identifiable sheets

extension VerifyReport: Identifiable {
    var id: String { "\(header.label)-\(header.createdAt.timeIntervalSince1970)" }
}

extension UTType {
    /// The `.catcher` container. Declared as a dynamic type so the file
    /// importer can grey out everything else.
    static let catcherArchive = UTType(exportedAs: "appcatcher.archive")
}
