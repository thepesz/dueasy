import SwiftUI
import UIKit
import os

/// App settings view.
/// Configures reminder defaults, calendar preferences, security, and displays app info.
///
/// UI STYLE: Adapts to the current UI style (Midnight Aurora, Paper Minimal, Warm Finance)
/// based on user preference from SettingsManager.uiStyleOtherViews.
struct SettingsView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.appLockManager) private var appLockManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var calendarPermissionGranted = false
    @State private var notificationPermissionGranted = false

    /// Current UI style from settings
    private var currentStyle: UIStyleProposal {
        environment.settingsManager.uiStyle(for: .otherViews)
    }

    /// Design tokens for the current style
    private var tokens: UIStyleTokens {
        UIStyleTokens(style: currentStyle)
    }

    /// Whether using Aurora style
    private var isAurora: Bool {
        currentStyle == .midnightAurora
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Style-aware background
                StyledSettingsBackground()

                if isAurora {
                    auroraSettingsList
                } else {
                    standardSettingsList
                }
            }
            .navigationTitle(L10n.Settings.title.localized)
            .task {
                await checkPermissions()
            }
        }
        // Apply UI style to the environment
        .environment(\.uiStyle, currentStyle)
    }

    // MARK: - Aurora Settings List

    @ViewBuilder
    private var auroraSettingsList: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // Permissions section (show if any permission is not granted)
                if !calendarPermissionGranted || !notificationPermissionGranted {
                    AuroraListSection(content: {
                        AuroraNavigationRow(showDivider: false) {
                            PermissionSettingsView(
                                calendarGranted: $calendarPermissionGranted,
                                notificationGranted: $notificationPermissionGranted
                            )
                            .environment(environment)
                            .environment(\.uiStyle, currentStyle)
                        } label: {
                            AuroraSettingsRow(
                                icon: "checkmark.shield.fill",
                                iconColor: .blue,
                                title: L10n.Settings.permissions.localized,
                                subtitle: permissionSummary
                            )
                        }
                    }, header: {
                        Text(L10n.Settings.permissionsSection.localized)
                    }, footer: {
                        EmptyView()
                    })
                }

                // Reminders section
                AuroraListSection(content: {
                    AuroraNavigationRow(showDivider: false) {
                        ReminderSettingsView()
                            .environment(environment)
                            .environment(\.uiStyle, currentStyle)
                    } label: {
                        AuroraSettingsRow(
                            icon: "bell.fill",
                            iconColor: .orange,
                            title: L10n.Settings.reminders.localized,
                            subtitle: reminderSummary
                        )
                    }
                }, header: {
                    Text(L10n.Settings.notificationsSection.localized)
                }, footer: {
                    EmptyView()
                })

                // Calendar section
                AuroraListSection(content: {
                    AuroraNavigationRow(showDivider: true) {
                        CalendarSettingsView()
                            .environment(environment)
                            .environment(\.uiStyle, currentStyle)
                    } label: {
                        AuroraSettingsRow(
                            icon: "calendar",
                            iconColor: .red,
                            title: L10n.Settings.calendar.localized,
                            subtitle: calendarSummary
                        )
                    }

                    // Recurring Payments row - navigates to RecurringOverviewView
                    AuroraNavigationRow(showDivider: false) {
                        RecurringOverviewView()
                            .environment(environment)
                            .environment(\.uiStyle, currentStyle)
                    } label: {
                        AuroraSettingsRow(
                            icon: "arrow.triangle.2.circlepath",
                            iconColor: AuroraPalette.accentBlue,
                            title: L10n.Recurring.overviewTitle.localized,
                            subtitle: recurringSummary
                        )
                    }
                }, header: {
                    Text(L10n.Settings.calendarSection.localized)
                }, footer: {
                    EmptyView()
                })

                // Security section
                AuroraListSection(content: {
                    AuroraNavigationRow(showDivider: false) {
                        SecuritySettingsView()
                            .environment(\.appLockManager, appLockManager)
                            .environment(\.uiStyle, currentStyle)
                    } label: {
                        AuroraSettingsRow(
                            icon: "lock.shield.fill",
                            iconColor: .purple,
                            title: L10n.Security.title.localized,
                            subtitle: securitySummary
                        )
                    }
                }, header: {
                    Text(L10n.Security.section.localized)
                }, footer: {
                    EmptyView()
                })

                // Appearance section
                auroraAppearanceSection

                // Language & Currency section
                auroraLanguageCurrencySection

                // About section
                AuroraListSection(content: {
                    AuroraNavigationRow(showDivider: true) {
                        AboutView()
                            .environment(\.uiStyle, currentStyle)
                    } label: {
                        AuroraSettingsRow(
                            icon: "info.circle.fill",
                            iconColor: .blue,
                            title: L10n.Settings.aboutDuEasy.localized,
                            subtitle: nil
                        )
                    }

                    AuroraNavigationRow(showDivider: false) {
                        PrivacyInfoView()
                            .environment(\.uiStyle, currentStyle)
                    } label: {
                        AuroraSettingsRow(
                            icon: "hand.raised.fill",
                            iconColor: .green,
                            title: L10n.Settings.privacy.localized,
                            subtitle: L10n.Settings.privacySubtitle.localized
                        )
                    }
                }, header: {
                    Text(L10n.Settings.aboutSection.localized)
                }, footer: {
                    EmptyView()
                })
            }
            .padding(.vertical, Spacing.md)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var auroraAppearanceSection: some View {
        AuroraListSection(content: {
            // Demo links (for reference)
            AuroraNavigationRow(showDivider: true) {
                MidnightAuroraHomeDemo()
            } label: {
                AuroraSettingsRow(
                    icon: "moon.stars.fill",
                    iconColor: AuroraPalette.accentBlue,
                    title: "Proposal 1: Midnight Aurora (Home)",
                    subtitle: "Bold, premium, luxurious"
                )
            }

            AuroraNavigationRow(showDivider: true) {
                MidnightAuroraOtherDemo()
            } label: {
                AuroraSettingsRow(
                    icon: "moon.stars.fill",
                    iconColor: AuroraPalette.accentPurple,
                    title: "Proposal 1: Midnight Aurora (Other)",
                    subtitle: "Document list view"
                )
            }

            AuroraNavigationRow(showDivider: true) {
                PaperMinimalHomeDemo()
            } label: {
                AuroraSettingsRow(
                    icon: "doc.plaintext.fill",
                    iconColor: .gray,
                    title: "Proposal 2: Paper Minimal (Home)",
                    subtitle: "Calm, focused, professional"
                )
            }

            AuroraNavigationRow(showDivider: true) {
                PaperMinimalOtherDemo()
            } label: {
                AuroraSettingsRow(
                    icon: "doc.plaintext.fill",
                    iconColor: Color.white.opacity(0.8),
                    title: "Proposal 2: Paper Minimal (Other)",
                    subtitle: "Document list view"
                )
            }

            AuroraNavigationRow(showDivider: true) {
                WarmFinanceHomeDemo()
            } label: {
                AuroraSettingsRow(
                    icon: "heart.fill",
                    iconColor: Color(red: 0.0, green: 0.6, blue: 0.6),
                    title: "Proposal 3: Warm Finance (Home)",
                    subtitle: "Friendly, trustworthy, organized"
                )
            }

            AuroraNavigationRow(showDivider: false) {
                WarmFinanceOtherDemo()
            } label: {
                AuroraSettingsRow(
                    icon: "heart.fill",
                    iconColor: Color(red: 0.95, green: 0.65, blue: 0.25),
                    title: "Proposal 3: Warm Finance (Other)",
                    subtitle: "Document list view"
                )
            }
        }, header: {
            Text(L10n.Settings.appearanceSection.localized)
        }, footer: {
            EmptyView()
        })
    }

    @ViewBuilder
    private var auroraLanguageCurrencySection: some View {
        AuroraListSection(content: {
            AuroraPickerRow(
                L10n.Language.appLanguage.localized,
                selection: Binding(
                    get: { environment.settingsManager.appLanguage },
                    set: { environment.settingsManager.appLanguage = $0 }
                ),
                options: SettingsManager.availableLanguages.map { ($0.code, $0.name) },
                showDivider: true
            )

            AuroraPickerRow(
                L10n.Settings.defaultCurrency.localized,
                selection: Binding(
                    get: { environment.settingsManager.defaultCurrency },
                    set: { environment.settingsManager.defaultCurrency = $0 }
                ),
                options: SettingsManager.availableCurrencies.map { ($0, $0) },
                showDivider: false
            )
        }, header: {
            Text(L10n.Settings.defaultsSection.localized)
        }, footer: {
            Text(L10n.Language.languageFooter.localized)
        })
    }

    // MARK: - Standard Settings List (non-Aurora)

    @ViewBuilder
    private var standardSettingsList: some View {
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

                // Recurring Payments row - navigates to RecurringOverviewView
                NavigationLink {
                    RecurringOverviewView()
                        .environment(environment)
                } label: {
                    SettingsRow(
                        icon: "arrow.triangle.2.circlepath",
                        iconColor: AppColors.primary,
                        title: L10n.Recurring.overviewTitle.localized,
                        subtitle: recurringSummary
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
                        title: L10n.Security.title.localized,
                        subtitle: securitySummary
                    )
                }
            } header: {
                Text(L10n.Security.section.localized)
            }

            // Appearance section (demo links for reference)
            Section {
                // Proposal 1: Midnight Aurora
                NavigationLink {
                    MidnightAuroraHomeDemo()
                } label: {
                    SettingsRow(
                        icon: "moon.stars.fill",
                        iconColor: AuroraPalette.accentBlue,
                        title: "Proposal 1: Midnight Aurora (Home)",
                        subtitle: "Bold, premium, luxurious"
                    )
                }

                NavigationLink {
                    MidnightAuroraOtherDemo()
                } label: {
                    SettingsRow(
                        icon: "moon.stars.fill",
                        iconColor: AuroraPalette.accentPurple,
                        title: "Proposal 1: Midnight Aurora (Other)",
                        subtitle: "Document list view"
                    )
                }

                // Proposal 2: Paper Minimal
                NavigationLink {
                    PaperMinimalHomeDemo()
                } label: {
                    SettingsRow(
                        icon: "doc.plaintext.fill",
                        iconColor: .gray,
                        title: "Proposal 2: Paper Minimal (Home)",
                        subtitle: "Calm, focused, professional"
                    )
                }

                NavigationLink {
                    PaperMinimalOtherDemo()
                } label: {
                    SettingsRow(
                        icon: "doc.plaintext.fill",
                        iconColor: .black,
                        title: "Proposal 2: Paper Minimal (Other)",
                        subtitle: "Document list view"
                    )
                }

                // Proposal 3: Warm Finance
                NavigationLink {
                    WarmFinanceHomeDemo()
                } label: {
                    SettingsRow(
                        icon: "heart.fill",
                        iconColor: Color(red: 0.0, green: 0.6, blue: 0.6),
                        title: "Proposal 3: Warm Finance (Home)",
                        subtitle: "Friendly, trustworthy, organized"
                    )
                }

                NavigationLink {
                    WarmFinanceOtherDemo()
                } label: {
                    SettingsRow(
                        icon: "heart.fill",
                        iconColor: Color(red: 0.95, green: 0.65, blue: 0.25),
                        title: "Proposal 3: Warm Finance (Other)",
                        subtitle: "Document list view"
                    )
                }
            } header: {
                Text(L10n.Settings.appearanceSection.localized)
            }

            // Language & Currency section
            Section {
                // Language picker
                Picker(L10n.Language.appLanguage.localized, selection: Binding(
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
                Text(L10n.Language.languageFooter.localized)
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
                return L10n.Security.faceIDEnabled.localized
            case .touchID:
                return L10n.Security.touchIDEnabled.localized
            case .none:
                return L10n.Security.passcodeEnabled.localized
            }
        }
        return L10n.Security.appLockDisabled.localized
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

    private var recurringSummary: String {
        L10n.Recurring.templatesSection.localized
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.uiStyle) private var style

    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?

    private var tokens: UIStyleTokens {
        UIStyleTokens(style: style)
    }

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

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.listRowPrimary)
                    .foregroundStyle(tokens.textPrimaryColor(for: colorScheme))

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(tokens.textSecondaryColor(for: colorScheme))
                }
            }
        }
    }
}

// MARK: - Reminder Settings View

struct ReminderSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.uiStyle) private var style

    private var isAurora: Bool {
        style == .midnightAurora
    }

    var body: some View {
        ZStack {
            if isAurora {
                StyledSettingsBackground()
            }

            if isAurora {
                auroraContent
            } else {
                standardContent
            }
        }
        .navigationTitle(L10n.Settings.reminders.localized)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var auroraContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                AuroraListSection(content: {
                    ForEach(Array(SettingsManager.availableReminderOffsets.enumerated()), id: \.element) { index, days in
                        AuroraToggleRow(
                            reminderLabel(for: days),
                            isOn: Binding(
                                get: {
                                    environment.settingsManager.defaultReminderOffsets.contains(days)
                                },
                                set: { enabled in
                                    toggleReminder(days: days, enabled: enabled)
                                }
                            ),
                            showDivider: index < SettingsManager.availableReminderOffsets.count - 1
                        )
                    }
                }, header: {
                    Text(L10n.Settings.defaultReminders.localized)
                }, footer: {
                    Text(L10n.Settings.remindersFooter.localized)
                })
            }
            .padding(.vertical, Spacing.md)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var standardContent: some View {
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
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
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
    @Environment(\.uiStyle) private var style

    private var isAurora: Bool {
        style == .midnightAurora
    }

    var body: some View {
        ZStack {
            if isAurora {
                StyledSettingsBackground()
            }

            if isAurora {
                auroraContent
            } else {
                standardContent
            }
        }
        .navigationTitle(L10n.Settings.calendar.localized)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var auroraContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                AuroraListSection(content: {
                    AuroraToggleRow(
                        L10n.Settings.useInvoicesCalendar.localized,
                        isOn: Binding(
                            get: { environment.settingsManager.useInvoicesCalendar },
                            set: { environment.settingsManager.useInvoicesCalendar = $0 }
                        ),
                        showDivider: false
                    )
                }, header: {
                    EmptyView()
                }, footer: {
                    Text(L10n.Settings.calendarFooter.localized)
                })

                AuroraListSection(content: {
                    AuroraToggleRow(
                        L10n.Settings.syncRecurringToiOSCalendar.localized,
                        isOn: Binding(
                            get: { environment.settingsManager.syncRecurringToiOSCalendar },
                            set: { environment.settingsManager.syncRecurringToiOSCalendar = $0 }
                        ),
                        showDivider: false
                    )
                }, header: {
                    EmptyView()
                }, footer: {
                    Text(L10n.Settings.syncRecurringToiOSCalendarFooter.localized)
                })
            }
            .padding(.vertical, Spacing.md)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var standardContent: some View {
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

            Section {
                Toggle(
                    L10n.Settings.syncRecurringToiOSCalendar.localized,
                    isOn: Binding(
                        get: { environment.settingsManager.syncRecurringToiOSCalendar },
                        set: { environment.settingsManager.syncRecurringToiOSCalendar = $0 }
                    )
                )
            } footer: {
                Text(L10n.Settings.syncRecurringToiOSCalendarFooter.localized)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.uiStyle) private var style

    private var isAurora: Bool {
        style == .midnightAurora
    }

    var body: some View {
        ZStack {
            if isAurora {
                StyledSettingsBackground()
            }

            if isAurora {
                auroraContent
            } else {
                standardContent
            }
        }
        .navigationTitle(L10n.Settings.aboutDuEasy.localized)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var auroraContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                AuroraListSection(content: {
                    AuroraInfoRow(
                        L10n.Settings.version.localized,
                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                        showDivider: true
                    )

                    AuroraInfoRow(
                        L10n.Settings.build.localized,
                        value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1",
                        showDivider: false
                    )
                }, header: {
                    EmptyView()
                }, footer: {
                    EmptyView()
                })

                AuroraListSection(content: {
                    AuroraListRow(showDivider: false) {
                        Text(L10n.Settings.aboutDescription.localized)
                            .font(Typography.body)
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }, header: {
                    Text(L10n.Settings.aboutSection.localized)
                }, footer: {
                    EmptyView()
                })
            }
            .padding(.vertical, Spacing.md)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var standardContent: some View {
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
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }
}

// MARK: - Privacy Info View

struct PrivacyInfoView: View {

    @Environment(\.uiStyle) private var style
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
            // Style-aware background
            StyledSettingsBackground()
                .ignoresSafeArea()

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
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, Spacing.md, for: .scrollContent)
            .contentMargins(.bottom, Spacing.xxl, for: .scrollContent)
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
    @Environment(\.uiStyle) private var style

    let icon: String
    let color: Color
    let title: String
    let description: String

    private var isAurora: Bool {
        style == .midnightAurora
    }

    // Aurora card colors
    private let cardBackingColor = Color(red: 0.08, green: 0.08, blue: 0.14)
    private let cardGlassLayer = Color.white.opacity(0.08)
    private let cardBorder = Color.white.opacity(0.15)

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // Icon with gradient ring
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(isAurora ? 0.3 : 0.2), color.opacity(isAurora ? 0.1 : 0.05)],
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
                            colors: [color.opacity(isAurora ? 0.6 : 0.5), color.opacity(isAurora ? 0.3 : 0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
            .shadow(color: isAurora ? color.opacity(0.3) : .clear, radius: 4, y: 2)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.listRowPrimary)
                    .foregroundStyle(isAurora ? Color.white : .primary)

                Text(description)
                    .font(Typography.bodyText)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.7) : .secondary)
                    .lineSpacing(4)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isAurora {
                // Aurora 4-layer card system
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(cardBackingColor)

                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(cardGlassLayer)

                    // Subtle accent tint
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.1), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            } else if reduceTransparency {
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
                        colors: isAurora
                            ? [Color.white.opacity(0.25), Color.white.opacity(0.1)]
                            : [
                                Color.white.opacity(colorScheme == .light ? 0.6 : 0.2),
                                Color.white.opacity(0.1)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isAurora ? 1 : 0.5
                )
        }
        .shadow(color: isAurora ? Color.black.opacity(0.3) : Color.black.opacity(0.06), radius: isAurora ? 12 : 8, y: isAurora ? 6 : 4)
    }
}

// MARK: - Security Settings View

struct SecuritySettingsView: View {
    @Environment(\.appLockManager) private var appLockManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.uiStyle) private var style
    @State private var showBiometricUnavailableAlert = false

    private var isAurora: Bool {
        style == .midnightAurora
    }

    var body: some View {
        ZStack {
            if isAurora {
                StyledSettingsBackground()
            }

            if isAurora {
                auroraContent
            } else {
                standardContent
            }
        }
        .navigationTitle(L10n.Security.title.localized)
        .navigationBarTitleDisplayMode(.inline)
        .alert(L10n.Security.biometricUnavailable.localized, isPresented: $showBiometricUnavailableAlert) {
            Button(L10n.Common.ok.localized, role: .cancel) { }
        } message: {
            Text(appLockManager.biometricUnavailableReason ?? L10n.Security.biometricUnavailable.localized)
        }
    }

    // MARK: - Aurora Content

    @ViewBuilder
    private var auroraContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // App Lock Toggle Section
                AuroraListSection(content: {
                    auroraAppLockToggle
                }, header: {
                    Text(L10n.Security.appLock.localized)
                }, footer: {
                    Text(L10n.Security.appLockFooter.localized)
                })

                // Lock Timeout (only show if enabled)
                if appLockManager.isEnabled {
                    AuroraListSection(content: {
                        AuroraPickerRow(
                            L10n.Security.lockTimeout.localized,
                            selection: Binding(
                                get: { Int(appLockManager.lockTimeout) },
                                set: { appLockManager.lockTimeout = TimeInterval($0) }
                            ),
                            options: [
                                (0, L10n.Security.lockImmediately.localized),
                                (60, L10n.Security.lockAfter1Min.localized),
                                (300, L10n.Security.lockAfter5Min.localized),
                                (900, L10n.Security.lockAfter15Min.localized),
                                (1800, L10n.Security.lockAfter30Min.localized)
                            ],
                            showDivider: false
                        )
                    }, header: {
                        Text(L10n.Security.lockTimeoutSection.localized)
                    }, footer: {
                        Text(L10n.Security.lockTimeoutFooter.localized)
                    })
                }

                // Biometric Status Section
                AuroraListSection(content: {
                    auroraBiometricStatusRow
                }, header: {
                    EmptyView()
                }, footer: {
                    if !appLockManager.isBiometricAvailable {
                        Text(appLockManager.biometricUnavailableReason ?? L10n.Security.biometricUnavailable.localized)
                    } else {
                        EmptyView()
                    }
                })

                // Data Protection Info Section
                AuroraListSection(content: {
                    auroraDataProtectionContent
                }, header: {
                    Text(L10n.Security.dataProtection.localized)
                }, footer: {
                    EmptyView()
                })
            }
            .padding(.vertical, Spacing.md)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var auroraAppLockToggle: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: biometricIcon)
                    .font(.title3)
                    .foregroundStyle(AuroraPalette.accentPurple)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(biometricTitle)
                        .font(Typography.listRowPrimary)
                        .foregroundStyle(Color.white)

                    Text(biometricSubtitle)
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { appLockManager.isEnabled },
                    set: { newValue in
                        if newValue && !appLockManager.isBiometricAvailable {
                            showBiometricUnavailableAlert = true
                        }
                        appLockManager.isEnabled = newValue
                    }
                ))
                .labelsHidden()
                .tint(AuroraPalette.accentBlue)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    @ViewBuilder
    private var auroraBiometricStatusRow: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(L10n.Security.biometricStatus.localized)
                        .font(Typography.listRowPrimary)
                        .foregroundStyle(Color.white)

                    Text(biometricStatusDescription)
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(appLockManager.isBiometricAvailable ? Color.green : Color.white.opacity(0.5))
                }

                Spacer()

                Image(systemName: appLockManager.isBiometricAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(appLockManager.isBiometricAvailable ? Color.green : Color.white.opacity(0.5))
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    @ViewBuilder
    private var auroraDataProtectionContent: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                AuroraInfoRowCompact(
                    icon: "lock.fill",
                    title: L10n.Security.fileProtection.localized,
                    description: L10n.Security.fileProtectionDesc.localized
                )

                AuroraInfoRowCompact(
                    icon: "icloud.slash.fill",
                    title: L10n.Security.noCloudBackup.localized,
                    description: L10n.Security.noCloudBackupDesc.localized
                )

                AuroraInfoRowCompact(
                    icon: "eye.slash.fill",
                    title: L10n.Security.privacyLogging.localized,
                    description: L10n.Security.privacyLoggingDesc.localized
                )
            }
            .padding(Spacing.md)
        }
    }

    // MARK: - Standard Content

    @ViewBuilder
    private var standardContent: some View {
        List {
            // App Lock Toggle
            Section {
                Toggle(isOn: Binding(
                    get: { appLockManager.isEnabled },
                    set: { newValue in
                        if newValue && !appLockManager.isBiometricAvailable {
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

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(biometricTitle)
                                .font(Typography.body)

                            Text(biometricSubtitle)
                                .font(Typography.caption1)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(L10n.Security.appLock.localized)
            } footer: {
                Text(L10n.Security.appLockFooter.localized)
            }

            // Lock Timeout (only show if enabled)
            if appLockManager.isEnabled {
                Section {
                    Picker(L10n.Security.lockTimeout.localized, selection: Binding(
                        get: { Int(appLockManager.lockTimeout) },
                        set: { appLockManager.lockTimeout = TimeInterval($0) }
                    )) {
                        Text(L10n.Security.lockImmediately.localized).tag(0)
                        Text(L10n.Security.lockAfter1Min.localized).tag(60)
                        Text(L10n.Security.lockAfter5Min.localized).tag(300)
                        Text(L10n.Security.lockAfter15Min.localized).tag(900)
                        Text(L10n.Security.lockAfter30Min.localized).tag(1800)
                    }
                } header: {
                    Text(L10n.Security.lockTimeoutSection.localized)
                } footer: {
                    Text(L10n.Security.lockTimeoutFooter.localized)
                }
            }

            // Biometric Status
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(L10n.Security.biometricStatus.localized)
                            .font(Typography.body)

                        Text(biometricStatusDescription)
                            .font(Typography.caption1)
                            .foregroundStyle(appLockManager.isBiometricAvailable ? AppColors.success : .secondary)
                    }

                    Spacer()

                    Image(systemName: appLockManager.isBiometricAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(appLockManager.isBiometricAvailable ? AppColors.success : .secondary)
                }
            } footer: {
                if !appLockManager.isBiometricAvailable {
                    Text(appLockManager.biometricUnavailableReason ?? L10n.Security.biometricUnavailable.localized)
                }
            }

            // Data Protection Info
            Section {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    InfoRow(
                        icon: "lock.fill",
                        title: L10n.Security.fileProtection.localized,
                        description: L10n.Security.fileProtectionDesc.localized
                    )

                    InfoRow(
                        icon: "icloud.slash.fill",
                        title: L10n.Security.noCloudBackup.localized,
                        description: L10n.Security.noCloudBackupDesc.localized
                    )

                    InfoRow(
                        icon: "eye.slash.fill",
                        title: L10n.Security.privacyLogging.localized,
                        description: L10n.Security.privacyLoggingDesc.localized
                    )
                }
                .padding(.vertical, Spacing.xs)
            } header: {
                Text(L10n.Security.dataProtection.localized)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
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
        case .faceID: return L10n.Security.requireFaceID.localized
        case .touchID: return L10n.Security.requireTouchID.localized
        case .none: return L10n.Security.requirePasscode.localized
        }
    }

    private var biometricSubtitle: String {
        L10n.Security.protectFinancialData.localized
    }

    private var biometricStatusDescription: String {
        let type = appLockManager.availableBiometricType
        switch type {
        case .faceID: return L10n.Security.faceIDAvailable.localized
        case .touchID: return L10n.Security.touchIDAvailable.localized
        case .none: return L10n.Security.usingPasscode.localized
        }
    }
}

/// Aurora-styled compact info row for data protection section
private struct AuroraInfoRowCompact: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(Typography.sectionIcon)
                .foregroundStyle(AuroraPalette.accentBlue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.bodyText)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.white)

                Text(description)
                    .font(Typography.stat)
                    .foregroundStyle(Color.white.opacity(0.6))
            }
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
                .font(Typography.sectionIcon)
                .foregroundStyle(AppColors.primary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.bodyText)
                    .fontWeight(.medium)

                Text(description)
                    .font(Typography.stat)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Permission Settings View

struct PermissionSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.uiStyle) private var style
    @Binding var calendarGranted: Bool
    @Binding var notificationGranted: Bool
    @State private var isRequesting = false

    private var isAurora: Bool {
        style == .midnightAurora
    }

    var body: some View {
        ZStack {
            if isAurora {
                StyledSettingsBackground()
            }

            if isAurora {
                auroraContent
            } else {
                standardContent
            }
        }
        .navigationTitle(L10n.Settings.permissions.localized)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshPermissions()
        }
    }

    // MARK: - Aurora Content

    @ViewBuilder
    private var auroraContent: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                // Calendar permission
                AuroraListSection(content: {
                    auroraPermissionRow(
                        title: L10n.Settings.calendarPermission.localized,
                        subtitle: calendarGranted
                            ? L10n.Settings.calendarPermissionGranted.localized
                            : L10n.Settings.calendarPermissionDenied.localized,
                        isGranted: calendarGranted,
                        onRequest: requestCalendarPermission
                    )
                }, header: {
                    EmptyView()
                }, footer: {
                    if !calendarGranted {
                        Text(L10n.Review.calendarPermissionNeeded.localized)
                    } else {
                        EmptyView()
                    }
                })

                // Notification permission
                AuroraListSection(content: {
                    auroraPermissionRow(
                        title: L10n.Settings.notificationPermission.localized,
                        subtitle: notificationGranted
                            ? L10n.Settings.notificationPermissionGranted.localized
                            : L10n.Settings.notificationPermissionDenied.localized,
                        isGranted: notificationGranted,
                        onRequest: requestNotificationPermission
                    )
                }, header: {
                    EmptyView()
                }, footer: {
                    if !notificationGranted {
                        Text(L10n.Review.notificationPermissionNeeded.localized)
                    } else {
                        EmptyView()
                    }
                })

                // Open system settings
                AuroraListSection(content: {
                    VStack(spacing: 0) {
                        Button {
                            openAppSettings()
                        } label: {
                            HStack {
                                Image(systemName: "gear")
                                    .foregroundStyle(AuroraPalette.accentBlue)
                                Text(L10n.Settings.openSettings.localized)
                                    .foregroundStyle(AuroraPalette.accentBlue)
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                        }
                        .buttonStyle(AuroraRowButtonStyle())
                    }
                }, header: {
                    EmptyView()
                }, footer: {
                    Text(L10n.PermissionSettings.permissionsDeniedFooter.localized)
                })
            }
            .padding(.vertical, Spacing.md)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func auroraPermissionRow(
        title: String,
        subtitle: String,
        isGranted: Bool,
        onRequest: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(Typography.listRowPrimary)
                        .foregroundStyle(Color.white)
                    Text(subtitle)
                        .font(Typography.listRowSecondary)
                        .foregroundStyle(isGranted ? Color.green : Color.white.opacity(0.5))
                }

                Spacer()

                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                } else {
                    Button(L10n.Settings.grantPermissions.localized) {
                        onRequest()
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        Capsule()
                            .fill(AuroraPalette.accentBlue)
                    )
                    .disabled(isRequesting)
                    .opacity(isRequesting ? 0.6 : 1.0)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Standard Content

    @ViewBuilder
    private var standardContent: some View {
        List {
            // Calendar permission
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(L10n.Settings.calendarPermission.localized)
                            .font(Typography.listRowPrimary)
                        Text(calendarGranted
                            ? L10n.Settings.calendarPermissionGranted.localized
                            : L10n.Settings.calendarPermissionDenied.localized)
                            .font(Typography.listRowSecondary)
                            .foregroundStyle(calendarGranted ? AppColors.success : .secondary)
                    }

                    Spacer()

                    if calendarGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
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
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(L10n.Settings.notificationPermission.localized)
                            .font(Typography.listRowPrimary)
                        Text(notificationGranted
                            ? L10n.Settings.notificationPermissionGranted.localized
                            : L10n.Settings.notificationPermissionDenied.localized)
                            .font(Typography.listRowSecondary)
                            .foregroundStyle(notificationGranted ? AppColors.success : .secondary)
                    }

                    Spacer()

                    if notificationGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
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
                Text(L10n.PermissionSettings.permissionsDeniedFooter.localized)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
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
