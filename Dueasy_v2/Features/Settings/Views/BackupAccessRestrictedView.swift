import SwiftUI
import AuthenticationServices
import os.log

/// View shown when anonymous users attempt to access backup features.
/// Explains that Sign in with Apple is required and provides the sign-in flow.
///
/// Design: Follows Aurora Liquid Glass aesthetic with multi-layer glass cards,
/// proper blur/vibrancy, and accessibility fallbacks.
///
/// ## Feature Matrix Rule
/// - Anonymous users (not signed in with Apple): NO access to backup UI
/// - Signed in with Apple (free or pro): Full access to backup UI
struct BackupAccessRestrictedView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    @State private var isSigningIn = false
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var showWhyRequired = false
    @State private var appeared = false

    private let logger = Logger(subsystem: "com.dueasy.app", category: "BackupAccess")

    // MARK: - Computed Properties

    private var isAurora: Bool {
        style == .midnightAurora
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                // Hero section with icon
                heroSection
                    .padding(.top, Spacing.xl)

                // Benefits list
                benefitsSection

                // Sign in button
                signInSection

                // Why required expandable section
                whyRequiredSection
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .alert(L10n.Auth.signInErrorTitle.localized, isPresented: $showError) {
            Button(L10n.Common.ok.localized, role: .cancel) { }
            Button(L10n.Common.retry.localized) {
                Task { await signInWithApple() }
            }
        } message: {
            Text(errorMessage ?? L10n.Auth.signInErrorGeneric.localized)
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
    }

    // MARK: - Hero Section

    @ViewBuilder
    private var heroSection: some View {
        VStack(spacing: Spacing.lg) {
            // Icon with glass background
            ZStack {
                // Outer glow
                if isAurora && !reduceTransparency {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [AuroraPalette.accentBlue.opacity(0.3), AuroraPalette.accentBlue.opacity(0)],
                                center: .center,
                                startRadius: 40,
                                endRadius: 90
                            )
                        )
                        .frame(width: 180, height: 180)
                }

                // Glass circle
                Circle()
                    .fill(isAurora ? AuroraPalette.cardBacking : Color(UIColor.secondarySystemGroupedBackground))
                    .frame(width: 100, height: 100)
                    .overlay {
                        if isAurora && !reduceTransparency {
                            Circle().fill(AuroraPalette.cardGlass)
                        }
                    }
                    .overlay {
                        if isAurora {
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
                    }
                    .shadow(color: isAurora ? AuroraPalette.accentBlue.opacity(0.3) : .clear, radius: 16, y: 8)

                // Icon
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(isAurora ? AuroraPalette.accentBlue : AppColors.primary)
                    .symbolRenderingMode(.hierarchical)
            }

            // Title and subtitle
            VStack(spacing: Spacing.sm) {
                Text(L10n.Backup.AccessRestricted.title.localized)
                    .font(Typography.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(isAurora ? Color.white : .primary)
                    .multilineTextAlignment(.center)

                Text(L10n.Backup.AccessRestricted.subtitle.localized)
                    .font(Typography.body)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.7) : .secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, Spacing.md)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8), value: appeared)
    }

    // MARK: - Benefits Section

    @ViewBuilder
    private var benefitsSection: some View {
        VStack(spacing: Spacing.md) {
            benefitRow(
                icon: "arrow.triangle.2.circlepath",
                iconColor: AuroraPalette.accentBlue,
                title: L10n.Backup.AccessRestricted.benefit1Title.localized,
                description: L10n.Backup.AccessRestricted.benefit1Description.localized,
                delay: 0.1
            )

            benefitRow(
                icon: "iphone.and.arrow.forward",
                iconColor: AuroraPalette.accentPurple,
                title: L10n.Backup.AccessRestricted.benefit2Title.localized,
                description: L10n.Backup.AccessRestricted.benefit2Description.localized,
                delay: 0.2
            )

            benefitRow(
                icon: "lock.shield.fill",
                iconColor: AuroraPalette.success,
                title: L10n.Backup.AccessRestricted.benefit3Title.localized,
                description: L10n.Backup.AccessRestricted.benefit3Description.localized,
                delay: 0.3
            )
        }
    }

    @ViewBuilder
    private func benefitRow(icon: String, iconColor: Color, title: String, description: String, delay: Double) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            // Icon with colored background
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [iconColor, iconColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .shadow(color: iconColor.opacity(0.4), radius: 4, y: 2)

            // Text content
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(isAurora ? Color.white : .primary)

                Text(description)
                    .font(Typography.caption1)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)
                    .lineSpacing(2)
            }

            Spacer()
        }
        .padding(Spacing.md)
        .background {
            if isAurora {
                AuroraSectionBackground(cornerRadius: CornerRadius.md)
            } else {
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 15)
        .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8).delay(delay), value: appeared)
    }

    // MARK: - Sign In Section

    @ViewBuilder
    private var signInSection: some View {
        VStack(spacing: Spacing.md) {
            // Sign in with Apple button
            SignInWithAppleButton(
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { _ in
                    // Actual handling done in signInWithApple()
                }
            )
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
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
                    Task { await signInWithApple() }
                }
            }
        }
        .padding(.top, Spacing.md)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: appeared)
    }

    // MARK: - Why Required Section

    @ViewBuilder
    private var whyRequiredSection: some View {
        VStack(spacing: Spacing.sm) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showWhyRequired.toggle()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "questionmark.circle")
                        .font(.subheadline)

                    Text(L10n.Backup.AccessRestricted.whyRequired.localized)
                        .font(Typography.subheadline)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(showWhyRequired ? 180 : 0))
                }
                .foregroundStyle(isAurora ? Color.white.opacity(0.6) : .secondary)
            }
            .buttonStyle(.plain)

            if showWhyRequired {
                Text(L10n.Backup.AccessRestricted.whyRequiredExplanation.localized)
                    .font(Typography.caption1)
                    .foregroundStyle(isAurora ? Color.white.opacity(0.5) : Color.secondary.opacity(0.8))
                    .lineSpacing(3)
                    .padding(.top, Spacing.xs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Spacing.md)
        .background {
            if isAurora {
                AuroraSectionBackground(cornerRadius: CornerRadius.md)
            } else {
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(Color(UIColor.tertiarySystemGroupedBackground))
            }
        }
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: appeared)
    }

    // MARK: - Actions

    private func signInWithApple() async {
        isSigningIn = true
        errorMessage = nil

        do {
            // Link Apple credential to existing anonymous user
            try await environment.authService.linkAppleCredential()
            logger.info("Apple credential linked successfully from backup settings")

            // Refresh auth state so the view updates
            await environment.authBootstrapper.refreshState()
        } catch AuthError.appleSignInCancelled {
            // User cancelled - don't show error
            logger.info("Apple Sign In cancelled by user")
        } catch AuthError.credentialAlreadyLinked {
            // Apple account already linked to another user (from previous install)
            // Automatically recover by signing in with Apple (replaces anonymous session)
            logger.warning("Apple credential already linked - recovering existing account")

            do {
                // Sign in with Apple (automatically replaces current anonymous session)
                // This reconnects to the existing Firebase user and recovers their data
                try await environment.authService.signInWithApple()
                logger.info("Successfully recovered existing Apple account and data")

                // Refresh auth state
                await environment.authBootstrapper.refreshState()
            } catch {
                logger.error("Failed to recover existing account: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showError = true
            }
        } catch {
            logger.error("Apple Sign In failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
        }

        isSigningIn = false
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ZStack {
            StyledSettingsBackground()
            BackupAccessRestrictedView()
        }
        .navigationTitle(L10n.Backup.title.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
    .environment(AppEnvironment.preview)
    .environment(\.uiStyle, .midnightAurora)
}
