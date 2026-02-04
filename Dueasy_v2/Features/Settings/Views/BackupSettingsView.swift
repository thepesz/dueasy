import SwiftUI
import UniformTypeIdentifiers

/// Settings view for backup and restore functionality.
/// Supports manual export/import and optional iCloud auto-backup.
///
/// UI STYLE: Adapts to the current UI style (Midnight Aurora, Paper Minimal, Warm Finance)
/// based on user preference from SettingsManager.uiStyleOtherViews.
struct BackupSettingsView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - State

    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showExportPasswordSheet = false
    @State private var showImportFilePicker = false
    @State private var showImportPasswordSheet = false
    @State private var selectedImportURL: URL?

    @State private var exportPassword = ""
    @State private var exportPasswordConfirm = ""
    @State private var importPassword = ""

    @State private var showExportShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var exportResult: BackupExportResult?

    @State private var showImportResult = false
    @State private var importResult: BackupImportResult?

    @State private var showError = false
    @State private var errorMessage: String?

    // iCloud state
    @State private var iCloudEnabled = false
    @State private var showEnableiCloudSheet = false
    @State private var iCloudPassword = ""
    @State private var iCloudPasswordConfirm = ""

    private var isAurora: Bool {
        style == .midnightAurora
    }

    private var tokens: UIStyleTokens {
        UIStyleTokens(style: style)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Style-aware background
            StyledSettingsBackground()

            if isAurora {
                auroraContent
            } else {
                standardContent
            }
        }
        .navigationTitle(L10n.Backup.title.localized)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showExportPasswordSheet) {
            exportPasswordSheet
        }
        .sheet(isPresented: $showImportPasswordSheet) {
            importPasswordSheet
        }
        .sheet(isPresented: $showEnableiCloudSheet) {
            enableiCloudSheet
        }
        .sheet(isPresented: $showExportShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .fileImporter(
            isPresented: $showImportFilePicker,
            allowedContentTypes: [.data, UTType(filenameExtension: backupFileExtension) ?? .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert(L10n.Common.error.localized, isPresented: $showError) {
            Button(L10n.Common.ok.localized, role: .cancel) { }
        } message: {
            Text(errorMessage ?? L10n.Errors.unknown.localized)
        }
        .alert(L10n.Backup.importSuccess.localized, isPresented: $showImportResult) {
            Button(L10n.Common.ok.localized, role: .cancel) { }
        } message: {
            if let result = importResult {
                Text(importResultMessage(result))
            }
        }
    }

    // MARK: - Aurora Content

    @ViewBuilder
    private var auroraContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // Manual Backup Section
                AuroraListSection(content: {
                    // Export button
                    VStack(spacing: 0) {
                        Button {
                            showExportPasswordSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.title3)
                                    .foregroundStyle(AuroraPalette.accentBlue)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(L10n.Backup.exportButton.localized)
                                        .font(Typography.body)
                                        .foregroundStyle(Color.white)

                                    Text(L10n.Backup.exportDescription.localized)
                                        .font(Typography.caption1)
                                        .foregroundStyle(Color.white.opacity(0.6))
                                }

                                Spacer()

                                if isExporting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.white.opacity(0.35))
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                        }
                        .buttonStyle(AuroraRowButtonStyle())
                        .disabled(isExporting)

                        Rectangle()
                            .fill(AuroraPalette.separator)
                            .frame(height: 0.5)
                            .padding(.leading, Spacing.md)

                        // Import button
                        Button {
                            showImportFilePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.title3)
                                    .foregroundStyle(AuroraPalette.accentPurple)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(L10n.Backup.importButton.localized)
                                        .font(Typography.body)
                                        .foregroundStyle(Color.white)

                                    Text(L10n.Backup.importDescription.localized)
                                        .font(Typography.caption1)
                                        .foregroundStyle(Color.white.opacity(0.6))
                                }

                                Spacer()

                                if isImporting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.white.opacity(0.35))
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                        }
                        .buttonStyle(AuroraRowButtonStyle())
                        .disabled(isImporting)
                    }
                }, header: {
                    Text(L10n.Backup.section.localized)
                }, footer: {
                    Text(L10n.Backup.subtitle.localized)
                })

                // iCloud Auto-Backup Section (optional)
                AuroraListSection(content: {
                    VStack(spacing: 0) {
                        // Enable/Disable toggle
                        HStack {
                            Image(systemName: "icloud")
                                .font(.title3)
                                .foregroundStyle(iCloudEnabled ? AuroraPalette.success : Color.white.opacity(0.5))
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(L10n.Backup.iCloudTitle.localized)
                                    .font(Typography.body)
                                    .foregroundStyle(Color.white)

                                Text(iCloudStatusText)
                                    .font(Typography.caption1)
                                    .foregroundStyle(iCloudEnabled ? AuroraPalette.success : Color.white.opacity(0.6))
                            }

                            Spacer()

                            if iCloudEnabled {
                                Button(L10n.Backup.iCloudDisable.localized) {
                                    Task {
                                        await disableiCloudBackup()
                                    }
                                }
                                .font(Typography.caption1.weight(.semibold))
                                .foregroundStyle(AuroraPalette.error)
                            } else {
                                Button(L10n.Backup.iCloudEnable.localized) {
                                    showEnableiCloudSheet = true
                                }
                                .font(Typography.caption1.weight(.semibold))
                                .foregroundStyle(AuroraPalette.accentBlue)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                    }
                }, header: {
                    Text(L10n.Backup.iCloudSection.localized)
                }, footer: {
                    Text(L10n.Backup.iCloudDescription.localized)
                })
            }
            .padding(.vertical, Spacing.md)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Standard Content

    @ViewBuilder
    private var standardContent: some View {
        List {
            // Manual Backup Section
            Section {
                // Export button
                Button {
                    showExportPasswordSheet = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(AppColors.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(L10n.Backup.exportButton.localized)
                                .font(Typography.body)
                                .foregroundStyle(.primary)

                            Text(L10n.Backup.exportDescription.localized)
                                .font(Typography.caption1)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isExporting)

                // Import button
                Button {
                    showImportFilePicker = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundStyle(AppColors.primary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(L10n.Backup.importButton.localized)
                                .font(Typography.body)
                                .foregroundStyle(.primary)

                            Text(L10n.Backup.importDescription.localized)
                                .font(Typography.caption1)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isImporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isImporting)
            } header: {
                Text(L10n.Backup.section.localized)
            } footer: {
                Text(L10n.Backup.subtitle.localized)
            }

            // iCloud Auto-Backup Section
            Section {
                HStack {
                    Image(systemName: "icloud")
                        .foregroundStyle(iCloudEnabled ? AppColors.success : .secondary)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(L10n.Backup.iCloudTitle.localized)
                            .font(Typography.body)

                        Text(iCloudStatusText)
                            .font(Typography.caption1)
                            .foregroundStyle(iCloudEnabled ? AppColors.success : .secondary)
                    }

                    Spacer()

                    if iCloudEnabled {
                        Button(L10n.Backup.iCloudDisable.localized) {
                            Task {
                                await disableiCloudBackup()
                            }
                        }
                        .font(Typography.caption1.weight(.semibold))
                        .foregroundStyle(.red)
                    } else {
                        Button(L10n.Backup.iCloudEnable.localized) {
                            showEnableiCloudSheet = true
                        }
                        .font(Typography.caption1.weight(.semibold))
                    }
                }
            } header: {
                Text(L10n.Backup.iCloudSection.localized)
            } footer: {
                Text(L10n.Backup.iCloudDescription.localized)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    // MARK: - Export Password Sheet

    @ViewBuilder
    private var exportPasswordSheet: some View {
        NavigationStack {
            ZStack {
                if isAurora {
                    StyledSettingsBackground()
                }

                VStack(spacing: Spacing.lg) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AuroraPalette.accentBlue.opacity(0.3), AuroraPalette.accentPurple.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: "lock.shield")
                            .font(.system(size: 36))
                            .foregroundStyle(isAurora ? AuroraPalette.accentBlue : AppColors.primary)
                    }
                    .padding(.top, Spacing.lg)

                    // Title and description
                    VStack(spacing: Spacing.xs) {
                        Text(L10n.Backup.passwordTitle.localized)
                            .font(Typography.headline)
                            .foregroundStyle(isAurora ? Color.white : .primary)

                        Text(L10n.Backup.passwordHint.localized)
                            .font(Typography.body)
                            .foregroundStyle(isAurora ? Color.white.opacity(0.7) : .secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Spacing.lg)

                    // Password fields
                    VStack(spacing: Spacing.md) {
                        SecureField(L10n.Backup.passwordPlaceholder.localized, text: $exportPassword)
                            .textContentType(.newPassword)
                            .modifier(PasswordFieldModifier(isAurora: isAurora))

                        SecureField(L10n.Backup.passwordConfirmPlaceholder.localized, text: $exportPasswordConfirm)
                            .textContentType(.newPassword)
                            .modifier(PasswordFieldModifier(isAurora: isAurora))

                        // Password requirements
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: exportPassword.count >= 8 ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(exportPassword.count >= 8 ? AuroraPalette.success : (isAurora ? Color.white.opacity(0.4) : .secondary))

                            Text(L10n.Backup.passwordMinLength.localized)
                                .font(Typography.caption1)
                                .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)

                            Spacer()
                        }

                        if !exportPasswordConfirm.isEmpty && exportPassword != exportPasswordConfirm {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(AuroraPalette.error)

                                Text(L10n.Backup.passwordMismatch.localized)
                                    .font(Typography.caption1)
                                    .foregroundStyle(AuroraPalette.error)

                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.lg)

                    Spacer()

                    // Export button
                    Button {
                        Task {
                            await performExport()
                        }
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(L10n.Backup.exportButton.localized)
                            }
                        }
                        .font(Typography.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(exportButtonBackground)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                    }
                    .disabled(!isExportPasswordValid || isExporting)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                }
            }
            .navigationTitle(L10n.Backup.exportTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel.localized) {
                        showExportPasswordSheet = false
                        exportPassword = ""
                        exportPasswordConfirm = ""
                    }
                    .foregroundStyle(isAurora ? AuroraPalette.accentBlue : AppColors.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Import Password Sheet

    @ViewBuilder
    private var importPasswordSheet: some View {
        NavigationStack {
            ZStack {
                if isAurora {
                    StyledSettingsBackground()
                }

                VStack(spacing: Spacing.lg) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AuroraPalette.accentPurple.opacity(0.3), AuroraPalette.accentBlue.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: "lock.open")
                            .font(.system(size: 36))
                            .foregroundStyle(isAurora ? AuroraPalette.accentPurple : AppColors.primary)
                    }
                    .padding(.top, Spacing.lg)

                    // Title
                    VStack(spacing: Spacing.xs) {
                        Text(L10n.Backup.importTitle.localized)
                            .font(Typography.headline)
                            .foregroundStyle(isAurora ? Color.white : .primary)

                        Text(L10n.Backup.importConfirmMessage.localized)
                            .font(Typography.body)
                            .foregroundStyle(isAurora ? Color.white.opacity(0.7) : .secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Spacing.lg)

                    // Password field
                    SecureField(L10n.Backup.passwordPlaceholder.localized, text: $importPassword)
                        .textContentType(.password)
                        .modifier(PasswordFieldModifier(isAurora: isAurora))
                        .padding(.horizontal, Spacing.lg)

                    Spacer()

                    // Import button
                    Button {
                        Task {
                            await performImport()
                        }
                    } label: {
                        HStack {
                            if isImporting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(L10n.Backup.importButton.localized)
                            }
                        }
                        .font(Typography.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(importButtonBackground)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                    }
                    .disabled(importPassword.isEmpty || isImporting)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                }
            }
            .navigationTitle(L10n.Backup.importTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel.localized) {
                        showImportPasswordSheet = false
                        importPassword = ""
                        selectedImportURL = nil
                    }
                    .foregroundStyle(isAurora ? AuroraPalette.accentBlue : AppColors.primary)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Enable iCloud Sheet

    @ViewBuilder
    private var enableiCloudSheet: some View {
        NavigationStack {
            ZStack {
                if isAurora {
                    StyledSettingsBackground()
                }

                VStack(spacing: Spacing.lg) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AuroraPalette.accentBlue.opacity(0.3), AuroraPalette.accentTeal.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 36))
                            .foregroundStyle(isAurora ? AuroraPalette.accentBlue : AppColors.primary)
                    }
                    .padding(.top, Spacing.lg)

                    // Title and description
                    VStack(spacing: Spacing.xs) {
                        Text(L10n.Backup.iCloudSetupPassword.localized)
                            .font(Typography.headline)
                            .foregroundStyle(isAurora ? Color.white : .primary)

                        Text(L10n.Backup.iCloudDescription.localized)
                            .font(Typography.body)
                            .foregroundStyle(isAurora ? Color.white.opacity(0.7) : .secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, Spacing.lg)

                    // Password fields
                    VStack(spacing: Spacing.md) {
                        SecureField(L10n.Backup.passwordPlaceholder.localized, text: $iCloudPassword)
                            .textContentType(.newPassword)
                            .modifier(PasswordFieldModifier(isAurora: isAurora))

                        SecureField(L10n.Backup.passwordConfirmPlaceholder.localized, text: $iCloudPasswordConfirm)
                            .textContentType(.newPassword)
                            .modifier(PasswordFieldModifier(isAurora: isAurora))

                        // Password requirements
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: iCloudPassword.count >= 8 ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(iCloudPassword.count >= 8 ? AuroraPalette.success : (isAurora ? Color.white.opacity(0.4) : .secondary))

                            Text(L10n.Backup.passwordMinLength.localized)
                                .font(Typography.caption1)
                                .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)

                            Spacer()
                        }
                    }
                    .padding(.horizontal, Spacing.lg)

                    Spacer()

                    // Enable button
                    Button {
                        Task {
                            await enableiCloudBackup()
                        }
                    } label: {
                        Text(L10n.Backup.iCloudEnable.localized)
                            .font(Typography.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(iCloudButtonBackground)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                    }
                    .disabled(!isiCloudPasswordValid)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                }
            }
            .navigationTitle(L10n.Backup.iCloudTitle.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel.localized) {
                        showEnableiCloudSheet = false
                        iCloudPassword = ""
                        iCloudPasswordConfirm = ""
                    }
                    .foregroundStyle(isAurora ? AuroraPalette.accentBlue : AppColors.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Helpers

    private var isExportPasswordValid: Bool {
        exportPassword.count >= 8 && exportPassword == exportPasswordConfirm
    }

    private var isiCloudPasswordValid: Bool {
        iCloudPassword.count >= 8 && iCloudPassword == iCloudPasswordConfirm
    }

    private var iCloudStatusText: String {
        if iCloudEnabled {
            return L10n.Backup.iCloudLastBackup.localized // Would show actual date
        } else {
            return L10n.Backup.iCloudNeverBackedUp.localized
        }
    }

    private var exportButtonBackground: some ShapeStyle {
        if isExportPasswordValid {
            return AnyShapeStyle(LinearGradient(
                colors: [AuroraPalette.accentBlue, AuroraPalette.accentPurple],
                startPoint: .leading,
                endPoint: .trailing
            ))
        } else {
            return AnyShapeStyle(Color.gray.opacity(0.5))
        }
    }

    private var importButtonBackground: some ShapeStyle {
        if !importPassword.isEmpty {
            return AnyShapeStyle(LinearGradient(
                colors: [AuroraPalette.accentPurple, AuroraPalette.accentBlue],
                startPoint: .leading,
                endPoint: .trailing
            ))
        } else {
            return AnyShapeStyle(Color.gray.opacity(0.5))
        }
    }

    private var iCloudButtonBackground: some ShapeStyle {
        if isiCloudPasswordValid {
            return AnyShapeStyle(LinearGradient(
                colors: [AuroraPalette.accentBlue, AuroraPalette.accentTeal],
                startPoint: .leading,
                endPoint: .trailing
            ))
        } else {
            return AnyShapeStyle(Color.gray.opacity(0.5))
        }
    }

    private func importResultMessage(_ result: BackupImportResult) -> String {
        var lines: [String] = []

        if result.documentsCreated > 0 {
            lines.append(L10n.Backup.documentsCreated.localized(with: result.documentsCreated))
        }
        if result.documentsUpdated > 0 {
            lines.append(L10n.Backup.documentsUpdated.localized(with: result.documentsUpdated))
        }
        if result.documentsSkipped > 0 {
            lines.append(L10n.Backup.documentsSkipped.localized(with: result.documentsSkipped))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Actions

    private func performExport() async {
        isExporting = true

        do {
            let result = try await environment.backupService.exportBackup(password: exportPassword)
            exportResult = result
            exportedFileURL = result.fileURL

            // Close password sheet and show share sheet
            showExportPasswordSheet = false
            exportPassword = ""
            exportPasswordConfirm = ""

            // Small delay to allow sheet dismiss animation
            try? await Task.sleep(nanoseconds: 300_000_000)
            showExportShareSheet = true
        } catch let error as BackupError {
            errorMessage = error.localizedDescription
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isExporting = false
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            selectedImportURL = url
            showImportPasswordSheet = true

        case .failure(let error):
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func performImport() async {
        guard let url = selectedImportURL else { return }

        isImporting = true

        do {
            let result = try await environment.backupService.importBackup(from: url, password: importPassword)
            importResult = result

            // Close password sheet and show result
            showImportPasswordSheet = false
            importPassword = ""
            selectedImportURL = nil

            showImportResult = true
        } catch let error as BackupError {
            errorMessage = error.localizedDescription
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isImporting = false
    }

    private func enableiCloudBackup() async {
        do {
            try await environment.iCloudBackupService.enableAutoBackup(password: iCloudPassword)
            iCloudEnabled = true

            showEnableiCloudSheet = false
            iCloudPassword = ""
            iCloudPasswordConfirm = ""
        } catch let error as BackupError {
            errorMessage = error.localizedDescription
            showError = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func disableiCloudBackup() async {
        do {
            try await environment.iCloudBackupService.disableAutoBackup()
            iCloudEnabled = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Password Field Modifier

private struct PasswordFieldModifier: ViewModifier {
    let isAurora: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .fill(isAurora ? Color(red: 0.08, green: 0.08, blue: 0.14) : Color(UIColor.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                    .strokeBorder(isAurora ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isAurora ? Color.white : .primary)
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BackupSettingsView()
            .environment(AppEnvironment.preview)
            .environment(\.uiStyle, .midnightAurora)
    }
}
