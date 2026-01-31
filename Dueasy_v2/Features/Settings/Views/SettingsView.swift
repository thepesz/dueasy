import SwiftUI
import UIKit
import os.log

/// App settings view.
/// Configures reminder defaults, calendar preferences, and displays app info.
struct SettingsView: View {

    @Environment(AppEnvironment.self) private var environment
    @State private var calendarPermissionGranted = false
    @State private var notificationPermissionGranted = false

    private let logger = Logger(subsystem: "com.dueasy.app", category: "Settings")

    var body: some View {
        NavigationStack {
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
        logger.info("Calendar permission: \(calendarPermissionGranted)")

        let notificationStatus = await environment.notificationService.authorizationStatus
        notificationPermissionGranted = notificationStatus.isAuthorized
        logger.info("Notification permission: \(notificationPermissionGranted)")
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
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Label(L10n.Privacy.localProcessingTitle.localized, systemImage: "iphone")
                        .font(Typography.headline)

                    Text(L10n.Privacy.localProcessingDescription.localized)
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Label(L10n.Privacy.secureStorageTitle.localized, systemImage: "lock.shield")
                        .font(Typography.headline)

                    Text(L10n.Privacy.secureStorageDescription.localized)
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Label(L10n.Privacy.yourDataTitle.localized, systemImage: "hand.raised")
                        .font(Typography.headline)

                    Text(L10n.Privacy.yourDataDescription.localized)
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Label(L10n.Privacy.noAccountTitle.localized, systemImage: "person.crop.circle.badge.xmark")
                        .font(Typography.headline)

                    Text(L10n.Privacy.noAccountDescription.localized)
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.md)
        }
        .navigationTitle(L10n.Privacy.title.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Permission Settings View

struct PermissionSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Binding var calendarGranted: Bool
    @Binding var notificationGranted: Bool
    @State private var isRequesting = false

    private let logger = Logger(subsystem: "com.dueasy.app", category: "Permissions")

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
        logger.info("Requesting calendar permission from Settings...")

        Task {
            let granted = await environment.calendarService.requestAccess()
            await MainActor.run {
                calendarGranted = granted
                isRequesting = false
                logger.info("Calendar permission result: \(granted)")
            }
        }
    }

    private func requestNotificationPermission() {
        guard !isRequesting else { return }
        isRequesting = true
        logger.info("Requesting notification permission from Settings...")

        Task {
            let granted = await environment.notificationService.requestAuthorization()
            await MainActor.run {
                notificationGranted = granted
                isRequesting = false
                logger.info("Notification permission result: \(granted)")
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
