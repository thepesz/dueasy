import SwiftUI
import UIKit
import os

/// App settings view.
/// Configures reminder defaults, calendar preferences, security, and displays app info.
struct SettingsView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.appLockManager) private var appLockManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var calendarPermissionGranted = false
    @State private var notificationPermissionGranted = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Modern gradient background
                ListGradientBackground()

                List {
                // Permissions section (show if any permission is not granted)
                if !calendarPermissionGranted || !notificationPermissionGranted {
                    Section {
                        NavigationLink {
                            PermissionSettingsView(
                                calendarGranted: $calendarPermissionGranted,
                                notificationGranted: $notificationPermissionGranted
                            )
                            .environment(environment)
                        } label: {
                            SettingsRow(
                                icon: "checkmark.shield.fill",
                                iconColor: .blue,
                                title: L10n.Settings.permissions.localized,
                                subtitle: permissionSummary
                            )
                        }
                    } header: {
                        Text(L10n.Settings.permissionsSection.localized)
                    }
                }

                // Reminders section
                Section {
                    NavigationLink {
                        ReminderSettingsView()
                            .environment(environment)
                    } label: {
                        SettingsRow(
                            icon: "bell.fill",
                            iconColor: .orange,
                            title: L10n.Settings.reminders.localized,
                            subtitle: reminderSummary
                        )
                    }
                } header: {
                    Text(L10n.Settings.notificationsSection.localized)
                }

                // Calendar section
                Section {
                    NavigationLink {
                        CalendarSettingsView()
                            .environment(environment)
                    } label: {
                        SettingsRow(
                            icon: "calendar",
                            iconColor: .red,
                            title: L10n.Settings.calendar.localized,
                            subtitle: calendarSummary
                        )
                    }
                } header: {
                    Text(L10n.Settings.calendarSection.localized)
                }

                // Security section
                Section {
                    NavigationLink {
                        SecuritySettingsView()
                            .environment(\.appLockManager, appLockManager)
                    } label: {
                        SettingsRow(
                            icon: "lock.shield.fill",
                            iconColor: .purple,
                            title: "Security",
                            subtitle: securitySummary
                        )
                    }
                } header: {
                    Text("Security")
                }

                // Language & Currency section
                Section {
                    // Language picker
                    Picker("App Language", selection: Binding(
                        get: { environment.settingsManager.appLanguage },
                        set: { newLanguage in
                            environment.settingsManager.appLanguage = newLanguage
                        }
                    )) {
                        ForEach(SettingsManager.availableLanguages, id: \.code) { language in
                            Text(language.name).tag(language.code)
                        }
                    }

                    // Currency picker
                    Picker(L10n.Settings.defaultCurrency.localized, selection: Binding(
                        get: { environment.settingsManager.defaultCurrency },
                        set: { environment.settingsManager.defaultCurrency = $0 }
                    )) {
                        ForEach(SettingsManager.availableCurrencies, id: \.self) { currency in
                            Text(currency).tag(currency)
                        }
                    }
                } header: {
                    Text(L10n.Settings.defaultsSection.localized)
                } footer: {
                    Text("Language setting controls OCR recognition and UI language. Changes take effect on next scan.")
                }

                // About section
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        SettingsRow(
                            icon: "info.circle.fill",
                            iconColor: .blue,
                            title: L10n.Settings.aboutDuEasy.localized,
                            subtitle: nil
                        )
                    }

                    NavigationLink {
                        PrivacyInfoView()
                    } label: {
                        SettingsRow(
                            icon: "hand.raised.fill",
                            iconColor: .green,
                            title: L10n.Settings.privacy.localized,
                            subtitle: L10n.Settings.privacySubtitle.localized
                        )
                    }
                } header: {
                    Text(L10n.Settings.aboutSection.localized)
                }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle(L10n.Settings.title.localized)
            .task {
                await checkPermissions()
            }
        }
    }

    private var permissionSummary: String {
        var missing: [String] = []
        if !calendarPermissionGranted {
            missing.append(L10n.Settings.calendarPermission.localized)
        }
        if !notificationPermissionGranted {
            missing.append(L10n.Settings.notificationPermission.localized)
        }
        if missing.isEmpty {
            return L10n.Settings.calendarPermissionGranted.localized
        }
        return L10n.Settings.grantPermissions.localized
    }

    private func checkPermissions() async {
        let calendarStatus = await environment.calendarService.authorizationStatus
        calendarPermissionGranted = calendarStatus.hasWriteAccess
        PrivacyLogger.logPermissionResult(permission: "calendar", granted: calendarPermissionGranted)

        let notificationStatus = await environment.notificationService.authorizationStatus
        notificationPermissionGranted = notificationStatus.isAuthorized
        PrivacyLogger.logPermissionResult(permission: "notifications", granted: notificationPermissionGranted)
    }

    private var securitySummary: String {
        if appLockManager.isEnabled {
            let biometricType = appLockManager.availableBiometricType
            switch biometricType {
            case .faceID:
                return "Face ID enabled"
            case .touchID:
                return "Touch ID enabled"
            case .none:
                return "Passcode enabled"
            }
        }
        return "App lock disabled"
    }

    private var reminderSummary: String {
        let offsets = environment.settingsManager.defaultReminderOffsets
        if offsets.isEmpty {
            return L10n.Settings.noReminders.localized
        }
        return L10n.Settings.remindersConfigured.localized(with: offsets.count)
    }

    private var calendarSummary: String {
        environment.settingsManager.useInvoicesCalendar
            ? L10n.Settings.usingInvoicesCalendar.localized
            : L10n.Settings.usingDefaultCalendar.localized
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Icon with gradient background
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [iconColor, iconColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .shadow(color: iconColor.opacity(0.3), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.body)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Reminder Settings View

struct ReminderSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            Section {
                ForEach(SettingsManager.availableReminderOffsets, id: \.self) { days in
                    Toggle(
                        reminderLabel(for: days),
                        isOn: Binding(
                            get: {
                                environment.settingsManager.defaultReminderOffsets.contains(days)
                            },
                            set: { enabled in
                                toggleReminder(days: days, enabled: enabled)
                            }
                        )
                    )
                }
            } header: {
                Text(L10n.Settings.defaultReminders.localized)
            } footer: {
                Text(L10n.Settings.remindersFooter.localized)
            }
        }
        .navigationTitle(L10n.Settings.reminders.localized)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reminderLabel(for days: Int) -> String {
        switch days {
        case 0:
            return L10n.Settings.onDueDate.localized
        case 1:
            return L10n.Settings.oneDayBefore.localized
        default:
            return L10n.Settings.daysBefore.localized(with: days)
        }
    }

    private func toggleReminder(days: Int, enabled: Bool) {
        var offsets = environment.settingsManager.defaultReminderOffsets
        if enabled {
            if !offsets.contains(days) {
                offsets.append(days)
                offsets.sort(by: >)
            }
        } else {
            offsets.removeAll { $0 == days }
        }
        environment.settingsManager.defaultReminderOffsets = offsets
    }
}

// MARK: - Calendar Settings View

struct CalendarSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            Section {
                Toggle(
                    L10n.Settings.useInvoicesCalendar.localized,
                    isOn: Binding(
                        get: { environment.settingsManager.useInvoicesCalendar },
                        set: { environment.settingsManager.useInvoicesCalendar = $0 }
                    )
                )
            } footer: {
                Text(L10n.Settings.calendarFooter.localized)
            }
        }
        .navigationTitle(L10n.Settings.calendar.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About View

struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Text(L10n.Settings.version.localized)
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(L10n.Settings.build.localized)
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text(L10n.Settings.aboutDescription.localized)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.Settings.aboutSection.localized)
            }
        }
        .navigationTitle(L10n.Settings.aboutDuEasy.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Privacy Info View

struct PrivacyInfoView: View {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let privacyItems: [(icon: String, color: Color, titleKey: String, descKey: String)] = [
        ("iphone", .blue, "privacy.localProcessing.title", "privacy.localProcessing.description"),
        ("lock.shield", .green, "privacy.secureStorage.title", "privacy.secureStorage.description"),
        ("hand.raised", .orange, "privacy.yourData.title", "privacy.yourData.description"),
        ("person.crop.circle.badge.xmark", .purple, "privacy.noAccount.title", "privacy.noAccount.description")
    ]

    var body: some View {
        ZStack {
            ListGradientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(Array(privacyItems.enumerated()), id: \.offset) { index, item in
                        PrivacyCard(
                            icon: item.icon,
                            color: item.color,
                            title: item.titleKey.localized,
                            description: item.descKey.localized
                        )
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 15)
                        .animation(
                            reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.08),
                            value: appeared
                        )
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(L10n.Privacy.title.localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.4)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
    }
}

struct PrivacyCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // Icon with gradient ring
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.2), color.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: icon)
                    .font(.title2.weight(.medium))
                    .foregroundStyle(color)
                    .symbolRenderingMode(.hierarchical)
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [color.opacity(0.5), color.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.headline)

                Text(description)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .fill(AppColors.secondaryBackground)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .light ? 0.5 : 0.1),
                                    Color.white.opacity(colorScheme == .light ? 0.2 : 0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .light ? 0.6 : 0.2),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 4)
    }
}

// MARK: - Security Settings View

struct SecuritySettingsView: View {
    @Environment(\.appLockManager) private var appLockManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showBiometricUnavailableAlert = false

    var body: some View {
        List {
            // App Lock Toggle
            Section {
                Toggle(isOn: Binding(
                    get: { appLockManager.isEnabled },
                    set: { newValue in
                        if newValue && !appLockManager.isBiometricAvailable {
                            // Show alert if biometrics not available
                            showBiometricUnavailableAlert = true
                        }
                        appLockManager.isEnabled = newValue
                    }
                )) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: biometricIcon)
                            .font(.title3)
                            .foregroundStyle(.purple)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(biometricTitle)
                                .font(Typography.body)

                            Text(biometricSubtitle)
                                .font(Typography.caption1)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("App Lock")
            } footer: {
                Text("When enabled, the app will require authentication to unlock after being in the background.")
            }

            // Lock Timeout (only show if enabled)
            if appLockManager.isEnabled {
                Section {
                    Picker("Lock Timeout", selection: Binding(
                        get: { Int(appLockManager.lockTimeout) },
                        set: { appLockManager.lockTimeout = TimeInterval($0) }
                    )) {
                        Text("Immediately").tag(0)
                        Text("After 1 minute").tag(60)
                        Text("After 5 minutes").tag(300)
                        Text("After 15 minutes").tag(900)
                        Text("After 30 minutes").tag(1800)
                    }
                } header: {
                    Text("Lock After")
                } footer: {
                    Text("How long the app can be in the background before requiring authentication.")
                }
            }

            // Biometric Status
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Biometric Status")
                            .font(Typography.body)

                        Text(biometricStatusDescription)
                            .font(Typography.caption1)
                            .foregroundStyle(appLockManager.isBiometricAvailable ? .green : .secondary)
                    }

                    Spacer()

                    Image(systemName: appLockManager.isBiometricAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(appLockManager.isBiometricAvailable ? .green : .secondary)
                }
            } footer: {
                if !appLockManager.isBiometricAvailable {
                    Text(appLockManager.biometricUnavailableReason ?? "Biometric authentication is not available on this device.")
                }
            }

            // Data Protection Info
            Section {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    InfoRow(
                        icon: "lock.fill",
                        title: "File Protection",
                        description: "All documents are encrypted when device is locked"
                    )

                    InfoRow(
                        icon: "icloud.slash.fill",
                        title: "No Cloud Backup",
                        description: "Scanned documents are excluded from iCloud backup"
                    )

                    InfoRow(
                        icon: "eye.slash.fill",
                        title: "Privacy Logging",
                        description: "Sensitive data is never logged or transmitted"
                    )
                }
                .padding(.vertical, Spacing.xs)
            } header: {
                Text("Data Protection")
            }
        }
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Biometric Not Available", isPresented: $showBiometricUnavailableAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(appLockManager.biometricUnavailableReason ?? "Biometric authentication is not available. The app will use device passcode instead.")
        }
    }

    private var biometricIcon: String {
        let type = appLockManager.availableBiometricType
        switch type {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock.fill"
        }
    }

    private var biometricTitle: String {
        let type = appLockManager.availableBiometricType
        switch type {
        case .faceID: return "Require Face ID"
        case .touchID: return "Require Touch ID"
        case .none: return "Require Passcode"
        }
    }

    private var biometricSubtitle: String {
        "Protect your financial data"
    }

    private var biometricStatusDescription: String {
        let type = appLockManager.availableBiometricType
        switch type {
        case .faceID: return "Face ID is available"
        case .touchID: return "Touch ID is available"
        case .none: return "Using device passcode"
        }
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(Typography.caption1)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Permission Settings View

struct PermissionSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Binding var calendarGranted: Bool
    @Binding var notificationGranted: Bool
    @State private var isRequesting = false

    var body: some View {
        List {
            // Calendar permission
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Settings.calendarPermission.localized)
                            .font(Typography.body)
                        Text(calendarGranted
                            ? L10n.Settings.calendarPermissionGranted.localized
                            : L10n.Settings.calendarPermissionDenied.localized)
                            .font(Typography.caption1)
                            .foregroundStyle(calendarGranted ? .green : .secondary)
                    }

                    Spacer()

                    if calendarGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(L10n.Settings.grantPermissions.localized) {
                            requestCalendarPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRequesting)
                    }
                }
            } footer: {
                if !calendarGranted {
                    Text(L10n.Review.calendarPermissionNeeded.localized)
                }
            }

            // Notification permission
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Settings.notificationPermission.localized)
                            .font(Typography.body)
                        Text(notificationGranted
                            ? L10n.Settings.notificationPermissionGranted.localized
                            : L10n.Settings.notificationPermissionDenied.localized)
                            .font(Typography.caption1)
                            .foregroundStyle(notificationGranted ? .green : .secondary)
                    }

                    Spacer()

                    if notificationGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(L10n.Settings.grantPermissions.localized) {
                            requestNotificationPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRequesting)
                    }
                }
            } footer: {
                if !notificationGranted {
                    Text(L10n.Review.notificationPermissionNeeded.localized)
                }
            }

            // Open system settings
            Section {
                Button {
                    openAppSettings()
                } label: {
                    HStack {
                        Image(systemName: "gear")
                        Text(L10n.Settings.openSettings.localized)
                    }
                }
            } footer: {
                Text("If permissions were previously denied, you may need to enable them in the Settings app.")
            }
        }
        .navigationTitle(L10n.Settings.permissions.localized)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshPermissions()
        }
    }

    private func requestCalendarPermission() {
        guard !isRequesting else { return }
        isRequesting = true

        Task {
            let granted = await environment.calendarService.requestAccess()
            await MainActor.run {
                calendarGranted = granted
                isRequesting = false
                PrivacyLogger.logPermissionResult(permission: "calendar", granted: granted)
            }
        }
    }

    private func requestNotificationPermission() {
        guard !isRequesting else { return }
        isRequesting = true

        Task {
            let granted = await environment.notificationService.requestAuthorization()
            await MainActor.run {
                notificationGranted = granted
                isRequesting = false
                PrivacyLogger.logPermissionResult(permission: "notifications", granted: granted)
            }
        }
    }

    private func refreshPermissions() async {
        let calendarStatus = await environment.calendarService.authorizationStatus
        calendarGranted = calendarStatus.hasWriteAccess

        let notificationStatus = await environment.notificationService.authorizationStatus
        notificationGranted = notificationStatus.isAuthorized
    }

    private func openAppSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(AppEnvironment.preview)
}
