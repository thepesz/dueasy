import SwiftUI

/// Reusable empty state view for lists and screens.
struct EmptyStateView: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    @State private var appeared = false

    init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: Spacing.xl) {
            // Icon with glass styling
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AppColors.primary.opacity(0.15), AppColors.primary.opacity(0)],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                // Glass circle
                glassCircle
                    .frame(width: 100, height: 100)
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .light ? 0.5 : 0.15),
                                        Color.white.opacity(0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    }
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

                Image(systemName: icon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(AppColors.primary.opacity(0.7))
                    .symbolRenderingMode(.hierarchical)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.8)
            .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.7), value: appeared)

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(Typography.title3)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8).delay(0.1), value: appeared)

            if let actionTitle = actionTitle, let action = action {
                PrimaryButton(actionTitle, icon: "plus") {
                    action()
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 15)
                .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !reduceMotion {
                withAnimation {
                    appeared = true
                }
            } else {
                appeared = true
            }
        }
    }

    @ViewBuilder
    private var glassCircle: some View {
        // PERFORMANCE: Uses CircleMaterial for optimized single-layer blur
        CircleMaterial(addHighlight: false)
    }
}

// MARK: - Preset Empty States

extension EmptyStateView {
    /// Empty state for document list
    static func noDocuments(onAdd: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "doc.text.magnifyingglass",
            title: L10n.Documents.noDocumentsTitle.localized,
            message: L10n.Documents.noDocumentsMessage.localized,
            actionTitle: L10n.Documents.noDocumentsAction.localized,
            action: onAdd
        )
    }

    /// Empty state for filtered list
    static func noResults(for filter: String) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: L10n.Documents.noResultsTitle.localized,
            message: L10n.Documents.noResultsMessage.localized(with: filter)
        )
    }

    /// Empty state for search
    static func noSearchResults(query: String) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: L10n.Documents.noResultsTitle.localized,
            message: L10n.Documents.noSearchResultsMessage.localized(with: query)
        )
    }
}

// MARK: - Preview

#Preview("Empty States") {
    TabView {
        EmptyStateView.noDocuments {}
            .tabItem { Label("No Documents", systemImage: "1.circle") }

        EmptyStateView.noResults(for: "Paid")
            .tabItem { Label("No Results", systemImage: "2.circle") }

        EmptyStateView.noSearchResults(query: "Acme")
            .tabItem { Label("No Search", systemImage: "3.circle") }
    }
}
