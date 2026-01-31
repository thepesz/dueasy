import SwiftUI

/// Full-screen loading indicator view.
struct LoadingView: View {

    let message: String?

    init(_ message: String? = nil) {
        self.message = message
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)

            if let message = message {
                Text(message)
                    .font(Typography.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background.opacity(0.8))
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
                .background(.ultraThinMaterial)
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
