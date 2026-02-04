import SwiftUI
import AuthenticationServices
import EventKit
import UserNotifications
import os.log

/// Onboarding flow for new users.
/// Presents value proposition, Sign in with Apple option, and requests necessary permissions.
///
/// ## User Flow
/// 1. Welcome page with app logo and value proposition
/// 2. Feature pages (scan, calendar, security)
/// 3. Sign in with Apple (optional) - links to anonymous Firebase user
/// 4. Permission request page (calendar, notifications)
struct OnboardingView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let onComplete: () -> Void

    @State private var currentPage = 0
    @State private var calendarPermissionGranted = false
    @State private var notificationPermissionGranted = false
    @State private var isRequestingPermission = false
    @State private var appeared = false

    // Sign in with Apple state
    @State private var isSigningInWithApple = false
    @State private var signInError: String?
    @State private var showSignInErrorAlert = false
    @State private var showCredentialAlreadyLinkedAlert = false

    private let logger = Logger(subsystem: "com.dueasy.app", category: "Onboarding")

    // Total pages: 3 info pages + 1 sign in page + 1 permission page
    private let totalPages = 5
    private let signInPageIndex = 3
    private let permissionPageIndex = 4

    private var infoPages: [OnboardingPage] {
        [
            OnboardingPage(
                icon: "doc.text.viewfinder",
                title: L10n.Onboarding.scanTitle.localized,
                description: L10n.Onboarding.scanDescription.localized,
                color: AuroraPalette.accentBlue
            ),
            OnboardingPage(
                icon: "calendar.badge.clock",
                title: L10n.Onboarding.calendarTitle.localized,
                description: L10n.Onboarding.calendarDescription.localized,
                color: AuroraPalette.warning
            ),
            OnboardingPage(
                icon: "lock.shield",
                title: L10n.Onboarding.securityTitle.localized,
                description: L10n.Onboarding.securityDescription.localized,
                color: AuroraPalette.success
            )
        ]
    }

    var body: some View {
        ZStack {
            // Aurora background
            EnhancedMidnightAuroraBackground()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    // Info pages
                    ForEach(Array(infoPages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                    }

                    // Sign in with Apple page
                    SignInPageView(
                        isSigningIn: $isSigningInWithApple,
                        onSignInWithApple: signInWithApple,
                        onSkip: skipSignIn
                    )
                    .tag(signInPageIndex)

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
                    // Modern page dots with animation
                    HStack(spacing: Spacing.sm) {
                        ForEach(0..<totalPages, id: \.self) { index in
                            Capsule()
                                .fill(index == currentPage ? AuroraPalette.accentBlue : Color.white.opacity(0.3))
                                .frame(width: index == currentPage ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                        }
                    }

                    // Action button
                    if currentPage != signInPageIndex {
                        PrimaryButton(
                            buttonTitle,
                            icon: currentPage == permissionPageIndex ? "arrow.right" : nil,
                            isLoading: isRequestingPermission
                        ) {
                            handleButtonTap()
                        }
                        .padding(.horizontal, Spacing.xl)
                        .disabled(isRequestingPermission)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: appeared)
                    }

                    // Skip button (not on last page or sign in page)
                    if currentPage < signInPageIndex {
                        Button(L10n.Common.skip.localized) {
                            // Skip to sign in page
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                currentPage = signInPageIndex
                            }
                        }
                        .font(Typography.subheadline.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
                .padding(.bottom, Spacing.xl)
            }
        }
        .task {
            await checkCurrentPermissions()
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.5)) {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
        .alert(L10n.Auth.signInErrorTitle.localized, isPresented: $showSignInErrorAlert) {
            Button(L10n.Common.ok.localized, role: .cancel) { }
            Button(L10n.Common.retry.localized) {
                Task { await signInWithApple() }
            }
        } message: {
            Text(signInError ?? L10n.Auth.signInErrorGeneric.localized)
        }
        .alert(L10n.Auth.credentialAlreadyLinkedTitle.localized, isPresented: $showCredentialAlreadyLinkedAlert) {
            Button(L10n.Auth.continueAsGuest.localized) {
                // Continue without linking
                proceedToPermissions()
            }
        } message: {
            Text(L10n.Auth.credentialAlreadyLinkedMessage.localized)
        }
    }

    private var buttonTitle: String {
        if currentPage == permissionPageIndex {
            return L10n.Common.getStarted.localized
        }
        return L10n.Common.continueButton.localized
    }

    private func handleButtonTap() {
        if currentPage < permissionPageIndex && currentPage != signInPageIndex {
            withAnimation {
                currentPage += 1
            }
        } else if currentPage == permissionPageIndex {
            // On permission page - complete onboarding
            logger.info("Completing onboarding - calendar: \(calendarPermissionGranted), notifications: \(notificationPermissionGranted)")
            onComplete()
        }
    }

    private func signInWithApple() async {
        isSigningInWithApple = true
        signInError = nil

        do {
            // Link Apple credential to existing anonymous user
            try await environment.authService.linkAppleCredential()
            logger.info("Apple credential linked successfully")

            // Proceed to permissions
            proceedToPermissions()
        } catch AuthError.appleSignInCancelled {
            // User cancelled - don't show error
            logger.info("Apple Sign In cancelled by user")
        } catch AuthError.credentialAlreadyLinked {
            // Apple account already linked to another user
            logger.warning("Apple credential already linked to another user")
            showCredentialAlreadyLinkedAlert = true
        } catch {
            logger.error("Apple Sign In failed: \(error.localizedDescription)")
            signInError = error.localizedDescription
            showSignInErrorAlert = true
        }

        isSigningInWithApple = false
    }

    private func skipSignIn() {
        logger.info("User skipped Apple Sign In")
        environment.settingsManager.didSkipAppleSignIn = true
        proceedToPermissions()
    }

    private func proceedToPermissions() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentPage = permissionPageIndex
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let page: OnboardingPage

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Icon with premium glass styling
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [page.color.opacity(0.3), page.color.opacity(0)],
                            center: .center,
                            startRadius: 50,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)

                // Glass circle background
                glassCircle(for: page)
                    .frame(width: 140, height: 140)
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [page.color.opacity(0.2), page.color.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        page.color.opacity(0.6),
                                        Color.white.opacity(0.2),
                                        page.color.opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                    .shadow(color: page.color.opacity(0.3), radius: 16, y: 8)

                // Icon
                Image(systemName: page.icon)
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(page.color)
                    .symbolRenderingMode(.hierarchical)
            }

            // Text content
            VStack(spacing: Spacing.md) {
                Text(page.title)
                    .font(Typography.title1)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .font(Typography.body)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.lg)
            }

            Spacer()
            Spacer()
        }
        .padding(Spacing.md)
    }

    @ViewBuilder
    private func glassCircle(for page: OnboardingPage) -> some View {
        if reduceTransparency {
            Circle()
                .fill(AuroraPalette.cardBacking)
        } else {
            Circle()
                .fill(AuroraPalette.cardBacking)
                .overlay {
                    Circle().fill(AuroraPalette.cardGlass)
                }
        }
    }
}

// MARK: - Sign In Page View

struct SignInPageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Binding var isSigningIn: Bool
    let onSignInWithApple: () async -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // App Logo
            VStack(spacing: Spacing.sm) {
                // Logo
                HStack(alignment: .bottom, spacing: 2) {
                    Text("Du")
                        .font(.system(
                            size: AuroraTypography.LogoDu.size,
                            weight: AuroraTypography.LogoDu.weight,
                            design: AuroraTypography.LogoDu.design
                        ))
                        .foregroundStyle(AuroraGradients.logoDu)

                    Text("Easy")
                        .font(.system(
                            size: AuroraTypography.LogoEasy.size,
                            weight: AuroraTypography.LogoEasy.weight,
                            design: AuroraTypography.LogoEasy.design
                        ))
                        .foregroundStyle(AuroraGradients.logoEasy)
                }

                // Tagline
                Text(L10n.Home.paymentTracker.localized)
                    .font(.system(
                        size: AuroraTypography.Tagline.size,
                        weight: AuroraTypography.Tagline.weight
                    ))
                    .tracking(AuroraTypography.Tagline.tracking)
                    .foregroundStyle(AuroraPalette.textSecondary)
                    .textCase(.uppercase)
            }

            Spacer()

            // Sign In Button Section
            VStack(spacing: Spacing.lg) {
                // Sign in with Apple button
                SignInWithAppleButton(
                    onRequest: { request in
                        request.requestedScopes = [.fullName, .email]
                    },
                    onCompletion: { _ in
                        // Handled by FirebaseAuthService
                    }
                )
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .cornerRadius(CornerRadius.md)
                .disabled(isSigningIn)
                .opacity(isSigningIn ? 0.6 : 1.0)
                .overlay {
                    if isSigningIn {
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(Color.black.opacity(0.3))
                            .overlay {
                                ProgressView()
                                    .tint(.white)
                            }
                    }
                }
                .onTapGesture {
                    if !isSigningIn {
                        Task { await onSignInWithApple() }
                    }
                }

                // Skip button
                Button(action: onSkip) {
                    Text(L10n.Auth.skipForNow.localized)
                        .font(Typography.body.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .disabled(isSigningIn)

                // Info text
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .top, spacing: Spacing.xs) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(AuroraPalette.textTertiary)

                        Text(L10n.Auth.withoutSignInInfo.localized)
                            .font(Typography.caption1)
                            .foregroundStyle(AuroraPalette.textTertiary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.sm)
            }
            .padding(.horizontal, Spacing.xl)

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
            ZStack {
                Circle()
                    .fill(AuroraPalette.cardBacking)
                    .overlay {
                        Circle().fill(AuroraPalette.cardGlass)
                    }
                    .frame(width: 120, height: 120)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [AuroraPalette.accentBlue.opacity(0.6), AuroraPalette.accentBlue.opacity(0.2)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                    .shadow(color: AuroraPalette.accentBlue.opacity(0.3), radius: 16, y: 8)

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(AuroraPalette.accentBlue)
            }

            // Title
            VStack(spacing: Spacing.sm) {
                Text(L10n.Onboarding.permissionsTitle.localized)
                    .font(Typography.title1)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)

                Text(L10n.Onboarding.permissionsDescription.localized)
                    .font(Typography.body)
                    .foregroundStyle(Color.white.opacity(0.7))
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
                        .foregroundStyle(AuroraPalette.success)
                    Text(L10n.Onboarding.allPermissionsGranted.localized)
                        .font(Typography.subheadline)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .padding(.top, Spacing.sm)
            } else {
                Text(L10n.Onboarding.permissionsOptional.localized)
                    .font(Typography.caption1)
                    .foregroundStyle(Color.white.opacity(0.5))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let icon: String
    let title: String
    let subtitle: String
    let isGranted: Bool
    let isLoading: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            if !isGranted && !isLoading {
                action()
            }
        }) {
            HStack(spacing: Spacing.md) {
                // Icon with gradient ring
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isGranted
                                    ? [AuroraPalette.success.opacity(0.3), AuroraPalette.success.opacity(0.1)]
                                    : [AuroraPalette.accentBlue.opacity(0.3), AuroraPalette.accentBlue.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.title2.weight(.medium))
                        .foregroundStyle(isGranted ? AuroraPalette.success : AuroraPalette.accentBlue)
                        .symbolRenderingMode(.hierarchical)
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: isGranted
                                    ? [AuroraPalette.success.opacity(0.5), AuroraPalette.success.opacity(0.2)]
                                    : [AuroraPalette.accentBlue.opacity(0.5), AuroraPalette.accentBlue.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.headline)
                        .foregroundStyle(Color.white)

                    Text(subtitle)
                        .font(Typography.caption1)
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                Spacer()

                // Status indicator
                if isLoading {
                    ProgressView()
                        .tint(AuroraPalette.accentBlue)
                } else if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AuroraPalette.success)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .offset(x: isPressed ? 3 : 0)
                }
            }
            .padding(Spacing.md)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(AuroraPalette.cardBacking)

                    RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                        .fill(AuroraPalette.cardGlass)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.25), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.3), radius: 12, y: 6)
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isGranted || isLoading)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !reduceMotion && !isPressed && !isGranted {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    if !reduceMotion {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isPressed = false
                        }
                    }
                }
        )
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(onComplete: {})
        .environment(AppEnvironment.preview)
}
