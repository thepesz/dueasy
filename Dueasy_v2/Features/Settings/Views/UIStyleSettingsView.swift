import SwiftUI

/// Settings view for selecting UI style proposals
/// Allows users to choose different visual styles for Home and Other Views independently
struct UIStyleSettingsView: View {

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                // Header explanation
                headerSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 15)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8),
                        value: appeared
                    )

                // Home View Style Section
                styleSection(
                    title: L10n.UIStyle.homeViewStyle.localized,
                    description: L10n.UIStyle.homeViewDescription.localized,
                    context: .home
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 15)
                .animation(
                    reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8).delay(0.08),
                    value: appeared
                )

                // Other Views Style Section
                styleSection(
                    title: L10n.UIStyle.otherViewsStyle.localized,
                    description: L10n.UIStyle.otherViewsDescription.localized,
                    context: .otherViews
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 15)
                .animation(
                    reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8).delay(0.16),
                    value: appeared
                )

                // Quick Actions
                quickActionsSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 15)
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8).delay(0.24),
                        value: appeared
                    )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background {
            ListGradientBackground()
        }
        .navigationTitle(L10n.UIStyle.title.localized)
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

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "paintpalette.fill")
                    .font(.title2)
                    .foregroundStyle(AppColors.primary)

                Text(L10n.UIStyle.headerTitle.localized)
                    .font(Typography.title3)
            }

            Text(L10n.UIStyle.headerDescription.localized)
                .font(Typography.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background {
            CardMaterial(cornerRadius: CornerRadius.lg, addHighlight: true)
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay {
            GlassBorder(cornerRadius: CornerRadius.lg, lineWidth: 0.5)
        }
    }

    // MARK: - Style Section

    @ViewBuilder
    private func styleSection(title: String, description: String, context: UIStyleContext) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Typography.headline)

                Text(description)
                    .font(Typography.caption1)
                    .foregroundStyle(.secondary)
            }

            // Style options
            VStack(spacing: Spacing.sm) {
                ForEach(UIStyleProposal.availableStyles) { style in
                    StyleOptionCard(
                        style: style,
                        isSelected: currentStyle(for: context) == style,
                        onSelect: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectStyle(style, for: context)
                            }
                        }
                    )
                }
            }
        }
        .padding(Spacing.md)
        .background {
            CardMaterial(cornerRadius: CornerRadius.lg, addHighlight: true)
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay {
            GlassBorder(cornerRadius: CornerRadius.lg, lineWidth: 0.5)
        }
    }

    // MARK: - Quick Actions Section

    @ViewBuilder
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(L10n.UIStyle.quickActions.localized)
                .font(Typography.headline)

            // Apply same style to all
            HStack(spacing: Spacing.sm) {
                ForEach(UIStyleProposal.availableStyles) { style in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            applyStyleToAll(style)
                        }
                    } label: {
                        VStack(spacing: Spacing.xs) {
                            // Mini preview gradient
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: style.previewColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 40)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                }

                            Text(L10n.UIStyle.applyAll.localized)
                                .font(Typography.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // Hint text
            Text(L10n.UIStyle.quickActionsHint.localized)
                .font(Typography.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.md)
        .background {
            CardMaterial(cornerRadius: CornerRadius.lg, addHighlight: true)
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
        .overlay {
            GlassBorder(cornerRadius: CornerRadius.lg, lineWidth: 0.5)
        }
    }

    // MARK: - Helpers

    private func currentStyle(for context: UIStyleContext) -> UIStyleProposal {
        environment.settingsManager.uiStyle(for: context)
    }

    private func selectStyle(_ style: UIStyleProposal, for context: UIStyleContext) {
        environment.settingsManager.setUIStyle(style, for: context)
    }

    private func applyStyleToAll(_ style: UIStyleProposal) {
        environment.settingsManager.uiStyleHome = style
        environment.settingsManager.uiStyleOtherViews = style
    }
}

// MARK: - Style Option Card

/// Card displaying a single style option with preview
struct StyleOptionCard: View {

    @Environment(\.colorScheme) private var colorScheme

    let style: UIStyleProposal
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.md) {
                // Preview gradient
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: style.previewColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay {
                        // Style icon
                        Image(systemName: style.iconName)
                            .font(.title2.weight(.medium))
                            .foregroundStyle(style == .paperMinimal ? Color.black : Color.white)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)

                // Text content
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(style.displayName)
                        .font(Typography.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(style.tagline)
                        .font(Typography.caption1)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // Selection indicator
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? AppColors.primary : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(AppColors.primary)
                            .frame(width: 16, height: 16)

                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(Spacing.sm)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .fill(AppColors.primary.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                                .strokeBorder(AppColors.primary.opacity(0.3), lineWidth: 1)
                        }
                } else {
                    RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.5))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Localization Keys
// MARK: - Preview

#Preview {
    NavigationStack {
        UIStyleSettingsView()
            .environment(AppEnvironment.preview)
    }
}
