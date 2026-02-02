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
        // VISUAL STYLE FIX: Use solid background instead of CircleMaterial to prevent
        // "Requesting visual style" errors when displayed in views with hidden navigation bars
        Circle()
            .fill(colorScheme == .light
                  ? Color(white: 0.98, opacity: 0.95)
                  : Color(white: 0.15, opacity: 0.95))
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
///
/// VISUAL STYLE FIX: Uses solid backgrounds instead of CardMaterial to prevent
/// "Requesting visual style in an implementation that has disabled it" errors.
/// This overlay may appear in views that are children of NavigationStacks with
/// hidden navigation bars, which disables the visual style system that materials depend on.
struct LoadingOverlay: View {

    @Environment(\.colorScheme) private var colorScheme

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
                // VISUAL STYLE FIX: Use solid background instead of CardMaterial
                // to avoid material effects that conflict with hidden navigation bars
                .background(loadingCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
            }
        }
    }

    /// Solid background for loading card that mimics glass appearance without materials
    private var loadingCardBackground: some ShapeStyle {
        colorScheme == .light
            ? Color(white: 0.98, opacity: 0.95)
            : Color(white: 0.15, opacity: 0.95)
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
