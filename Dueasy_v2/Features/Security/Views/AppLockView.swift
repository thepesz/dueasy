import SwiftUI

/// Full-screen lock view shown when app requires authentication.
/// Displays app branding, lock status, and authentication button.
/// Follows iOS 26 Liquid Glass design guidelines with accessibility support.
struct AppLockView: View {

    @Environment(\.appLockManager) private var lockManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showError: Bool = false
    @State private var pulseAnimation: Bool = false

    var body: some View {
        ZStack {
            // Background - blurred/opaque based on accessibility
            backgroundLayer

            // Content
            VStack(spacing: Spacing.xl) {
                Spacer()

                // Lock icon with animation
                lockIcon

                // Title and subtitle
                titleSection

                // Error message (if any)
                if let error = lockManager.lastError, showError {
                    errorMessage(error)
                }

                Spacer()

                // Unlock button
                unlockButton

                // Biometric type indicator
                biometricIndicator

                Spacer()
                    .frame(height: Spacing.xxl)
            }
            .padding(.horizontal, Spacing.lg)
        }
        .ignoresSafeArea()
        .onAppear {
            // Attempt authentication on appear
            if !lockManager.isAuthenticating {
                attemptAuthentication()
            }
        }
        .onChange(of: lockManager.lastError) { _, newError in
            showError = newError != nil
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if reduceTransparency {
            // Solid background for accessibility
            AppColors.background
                .ignoresSafeArea()
        } else {
            // Gradient background with blur effect
            ZStack {
                // Base color
                Color.black.opacity(0.85)

                // Gradient overlay
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.15),
                        Color.purple.opacity(0.1),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Frosted glass effect
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Lock Icon

    @ViewBuilder
    private var lockIcon: some View {
        ZStack {
            // Outer ring with pulse animation
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.blue.opacity(0.5), .purple.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 120, height: 120)
                .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                .opacity(pulseAnimation ? 0.5 : 0.8)

            // Inner circle background
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.2),
                            Color.purple.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 100, height: 100)

            // Lock icon
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)
        }
        .onAppear {
            startPulseAnimation()
        }
        .accessibilityLabel("App is locked")
    }

    // MARK: - Title Section

    private var titleSection: some View {
        VStack(spacing: Spacing.sm) {
            Text("DuEasy is Locked")
                .font(Typography.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text("Your financial data is protected")
                .font(Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Error Message

    private func errorMessage(_ error: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)

            Text(error)
                .font(Typography.caption1)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
                .fill(Color.orange.opacity(0.1))
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Unlock Button

    private var unlockButton: some View {
        Button {
            attemptAuthentication()
        } label: {
            HStack(spacing: Spacing.sm) {
                if lockManager.isAuthenticating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: biometricIcon)
                        .font(.title3)
                }

                Text(buttonText)
                    .font(Typography.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(lockManager.isAuthenticating)
        .padding(.horizontal, Spacing.lg)
        .accessibilityLabel(buttonText)
        .accessibilityHint("Double tap to authenticate and unlock the app")
    }

    // MARK: - Biometric Indicator

    @ViewBuilder
    private var biometricIndicator: some View {
        let biometricType = lockManager.availableBiometricType

        if biometricType != .none {
            HStack(spacing: Spacing.xs) {
                Image(systemName: biometricType.iconName)
                    .font(.caption)
                Text("\(biometricType.rawValue) enabled")
                    .font(Typography.caption2)
            }
            .foregroundStyle(.secondary)
        } else if let reason = lockManager.biometricUnavailableReason {
            Text(reason)
                .font(Typography.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
        }
    }

    // MARK: - Helpers

    private var biometricIcon: String {
        let type = lockManager.availableBiometricType
        switch type {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock.open.fill"
        }
    }

    private var buttonText: String {
        if lockManager.isAuthenticating {
            return "Authenticating..."
        }

        let type = lockManager.availableBiometricType
        switch type {
        case .faceID: return "Unlock with Face ID"
        case .touchID: return "Unlock with Touch ID"
        case .none: return "Unlock with Passcode"
        }
    }

    private func attemptAuthentication() {
        Task {
            await lockManager.authenticate()
        }
    }

    private func startPulseAnimation() {
        guard !reduceMotion else { return }

        withAnimation(
            .easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true)
        ) {
            pulseAnimation = true
        }
    }
}

// MARK: - Preview

#Preview("App Lock - Light") {
    AppLockView()
        .environment(\.appLockManager, AppLockManager())
        .preferredColorScheme(.light)
}

#Preview("App Lock - Dark") {
    AppLockView()
        .environment(\.appLockManager, AppLockManager())
        .preferredColorScheme(.dark)
}
