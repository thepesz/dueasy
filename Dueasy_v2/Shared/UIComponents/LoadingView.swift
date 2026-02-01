import SwiftUI

/// Full-screen loading indicator view.
struct LoadingView: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let message: String?

    init(_ message: String? = nil) {
        self.message = message
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Modern loading indicator with glass styling
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppColors.primary.opacity(0.1), AppColors.primary.opacity(0)],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                // Glass background
                glassCircle
                    .frame(width: 80, height: 80)
                    .overlay {
                        Circle()
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
                    .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)

                ProgressView()
                    .scaleEffect(1.5)
                    .tint(AppColors.primary)
            }

            if let message = message {
                Text(message)
                    .font(Typography.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var glassCircle: some View {
        // PERFORMANCE: Uses CircleMaterial for optimized single-layer blur
        CircleMaterial(addHighlight: false)
    }
}

/// Inline loading indicator for use within other views.
struct InlineLoadingView: View {

    let message: String?

    init(_ message: String? = nil) {
        self.message = message
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()

            if let message = message {
                Text(message)
                    .font(Typography.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.md)
    }
}

/// Loading overlay that can be placed over other content.
struct LoadingOverlay: View {

    let isLoading: Bool
    let message: String?

    init(isLoading: Bool, message: String? = nil) {
        self.isLoading = isLoading
        self.message = message
    }

    var body: some View {
        if isLoading {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: Spacing.md) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    if let message = message {
                        Text(message)
                            .font(Typography.subheadline)
                            .foregroundStyle(.white)
                    }
                }
                .padding(Spacing.xl)
                .background { CardMaterial(cornerRadius: CornerRadius.lg, addHighlight: false) }
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds a loading overlay to the view
    func loadingOverlay(isLoading: Bool, message: String? = nil) -> some View {
        ZStack {
            self

            LoadingOverlay(isLoading: isLoading, message: message)
        }
    }
}

// MARK: - Preview

#Preview("Loading Views") {
    VStack(spacing: Spacing.xl) {
        LoadingView("Loading documents...")

        Divider()

        InlineLoadingView("Processing...")

        Divider()

        Text("Content underneath")
            .frame(maxWidth: .infinity, maxHeight: 200)
            .background(Color.blue.opacity(0.2))
            .loadingOverlay(isLoading: true, message: "Scanning...")
    }
}
