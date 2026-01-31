import SwiftUI

/// Reusable empty state view for lists and screens.
struct EmptyStateView: View {

    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

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
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.title3)
                    .foregroundStyle(.primary)

                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle = actionTitle, let action = action {
                PrimaryButton(actionTitle, icon: "plus") {
                    action()
                }
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
