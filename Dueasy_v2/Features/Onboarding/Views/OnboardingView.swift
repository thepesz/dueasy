import SwiftUI
import EventKit
import UserNotifications
import os.log

/// Onboarding flow for new users.
/// Presents value proposition and requests necessary permissions.
struct OnboardingView: View {

    @Environment(AppEnvironment.self) private var environment

    let onComplete: () -> Void

    @State private var currentPage = 0
    @State private var calendarPermissionGranted = false
    @State private var notificationPermissionGranted = false
    @State private var isRequestingPermission = false

    private let logger = Logger(subsystem: "com.dueasy.app", category: "Onboarding")

    // Total pages: 3 info pages + 1 permission page
    private let totalPages = 4
    private let permissionPageIndex = 3

    private var infoPages: [OnboardingPage] {
        [
            OnboardingPage(
                icon: "doc.text.viewfinder",
                title: L10n.Onboarding.scanTitle.localized,
                description: L10n.Onboarding.scanDescription.localized,
                color: .blue
            ),
            OnboardingPage(
                icon: "calendar.badge.clock",
                title: L10n.Onboarding.calendarTitle.localized,
                description: L10n.Onboarding.calendarDescription.localized,
                color: .orange
            ),
            OnboardingPage(
                icon: "lock.shield",
                title: L10n.Onboarding.securityTitle.localized,
                description: L10n.Onboarding.securityDescription.localized,
                color: .green
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                // Info pages
                ForEach(Array(infoPages.enumerated()), id: \.offset) { index, page in
                    OnboardingPageView(page: page)
                        .tag(index)
                }

                // Permission request page
                PermissionRequestPageView(
                    calendarGranted: calendarPermissionGranted,
                    notificationGranted: notificationPermissionGranted,
                    isRequesting: isRequestingPermission,
                    onRequestCalendar: requestCalendarPermission,
                    onRequestNotification: requestNotificationPermission
                )
                .tag(permissionPageIndex)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Page indicator and button
            VStack(spacing: Spacing.lg) {
                // Page dots
                HStack(spacing: Spacing.xs) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? AppColors.primary : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut, value: currentPage)
                    }
                }

                // Action button
                PrimaryButton(
                    buttonTitle,
                    icon: currentPage == permissionPageIndex ? "arrow.right" : nil,
                    isLoading: isRequestingPermission
                ) {
                    handleButtonTap()
                }
                .padding(.horizontal, Spacing.xl)
                .disabled(isRequestingPermission)

                // Skip button (not on last page)
                if currentPage < permissionPageIndex {
                    Button(L10n.Common.skip.localized) {
                        // Skip to permissions page
                        withAnimation {
                            currentPage = permissionPageIndex
                        }
                    }
                    .font(Typography.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, Spacing.xl)
        }
        .background(AppColors.background)
        .task {
            await checkCurrentPermissions()
        }
    }

    private var buttonTitle: String {
        if currentPage == permissionPageIndex {
            if calendarPermissionGranted && notificationPermissionGranted {
                return L10n.Common.getStarted.localized
            } else {
                return L10n.Common.getStarted.localized
            }
        }
        return L10n.Common.continueButton.localized
    }

    private func handleButtonTap() {
        if currentPage < permissionPageIndex {
            withAnimation {
                currentPage += 1
            }
        } else {
            // On permission page - complete onboarding
            logger.info("Completing onboarding - calendar: \(calendarPermissionGranted), notifications: \(notificationPermissionGranted)")
            onComplete()
        }
    }

    private func checkCurrentPermissions() async {
        // Check calendar permission
        let calendarStatus = await environment.calendarService.authorizationStatus
        calendarPermissionGranted = calendarStatus.hasWriteAccess
        logger.info("Current calendar permission: \(String(describing: calendarStatus)), hasWriteAccess: \(calendarPermissionGranted)")

        // Check notification permission
        let notificationStatus = await environment.notificationService.authorizationStatus
        notificationPermissionGranted = notificationStatus.isAuthorized
        logger.info("Current notification permission: \(String(describing: notificationStatus)), isAuthorized: \(notificationPermissionGranted)")
    }

    private func requestCalendarPermission() {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        logger.info("Requesting calendar permission...")

        Task {
            let granted = await environment.calendarService.requestAccess()
            await MainActor.run {
                calendarPermissionGranted = granted
                isRequestingPermission = false
                logger.info("Calendar permission result: \(granted)")
            }
        }
    }

    private func requestNotificationPermission() {
        guard !isRequestingPermission else { return }
        isRequestingPermission = true
        logger.info("Requesting notification permission...")

        Task {
            let granted = await environment.notificationService.requestAuthorization()
            await MainActor.run {
                notificationPermissionGranted = granted
                isRequestingPermission = false
                logger.info("Notification permission result: \(granted)")
            }
        }
    }
}

// MARK: - Onboarding Page Data

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

// MARK: - Onboarding Page View

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundStyle(page.color)
                .padding(Spacing.xl)
                .background(page.color.opacity(0.12))
                .clipShape(Circle())

            // Text content
            VStack(spacing: Spacing.sm) {
                Text(page.title)
                    .font(Typography.title1)
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            Spacer()
            Spacer()
        }
        .padding(Spacing.md)
    }
}

// MARK: - Permission Request Page View

struct PermissionRequestPageView: View {
    let calendarGranted: Bool
    let notificationGranted: Bool
    let isRequesting: Bool
    let onRequestCalendar: () -> Void
    let onRequestNotification: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Icon
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
                .padding(Spacing.xl)
                .background(Color.blue.opacity(0.12))
                .clipShape(Circle())

            // Title
            VStack(spacing: Spacing.sm) {
                Text(L10n.Onboarding.permissionsTitle.localized)
                    .font(Typography.title1)
                    .multilineTextAlignment(.center)

                Text(L10n.Onboarding.permissionsDescription.localized)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }

            Spacer()

            // Permission buttons
            VStack(spacing: Spacing.md) {
                PermissionButton(
                    icon: "calendar",
                    title: L10n.Onboarding.calendarPermission.localized,
                    subtitle: L10n.Onboarding.calendarPermissionSubtitle.localized,
                    isGranted: calendarGranted,
                    isLoading: isRequesting && !calendarGranted,
                    action: onRequestCalendar
                )

                PermissionButton(
                    icon: "bell.fill",
                    title: L10n.Onboarding.notificationPermission.localized,
                    subtitle: L10n.Onboarding.notificationPermissionSubtitle.localized,
                    isGranted: notificationGranted,
                    isLoading: isRequesting && !notificationGranted,
                    action: onRequestNotification
                )
            }
            .padding(.horizontal, Spacing.lg)

            // Status message
            if calendarGranted && notificationGranted {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(L10n.Onboarding.allPermissionsGranted.localized)
                        .font(Typography.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, Spacing.sm)
            } else {
                Text(L10n.Onboarding.permissionsOptional.localized)
                    .font(Typography.caption1)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
            }

            Spacer()
        }
        .padding(Spacing.md)
    }
}

// MARK: - Permission Button

struct PermissionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let isGranted: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            if !isGranted && !isLoading {
                action()
            }
        }) {
            HStack(spacing: Spacing.md) {
                // Icon
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isGranted ? .green : AppColors.primary)
                    .frame(width: 44, height: 44)
                    .background(isGranted ? Color.green.opacity(0.12) : AppColors.primary.opacity(0.12))
                    .clipShape(Circle())

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.headline)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status indicator
                if isLoading {
                    ProgressView()
                } else if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Spacing.md)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isGranted || isLoading)
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(onComplete: {})
        .environment(AppEnvironment.preview)
}
