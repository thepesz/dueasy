import SwiftUI

/// Simple preview view to show the three UI style proposals
/// This is a simplified version without complex effects, just to show the concepts
struct UIStylePreviewView: View {

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Text("UI Style Proposals")
                        .font(.largeTitle.bold())

                    Text("Three dramatically different design approaches for DuEasy")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()

                // Proposal 1: Midnight Aurora
                proposalCard(
                    title: "🌌 Midnight Aurora",
                    subtitle: "Bold • Premium • Luxurious",
                    description: "Electric blue and purple-pink colors with animated floating orbs, glassmorphism, gradient cards, and glow effects. Fluid shapes with large corner radii.",
                    features: [
                        "Animated background orbs",
                        "Glass morphism effects",
                        "Gradient accent shadows",
                        "Bold typography"
                    ],
                    colors: [Color.blue, Color.purple, Color.pink],
                    cornerRadius: 20
                )

                // Proposal 2: Paper Minimal
                proposalCard(
                    title: "📄 Paper Minimal",
                    subtitle: "Calm • Focused • Professional",
                    description: "Pure black and white with no shadows or gradients. Completely flat design with sharp corners and clean horizontal lines. High contrast for maximum readability.",
                    features: [
                        "Zero visual effects",
                        "Sharp corners (4pt)",
                        "Horizontal separators",
                        "Medium weight typography"
                    ],
                    colors: [Color.black, Color.white, Color.gray],
                    cornerRadius: 4
                )

                // Proposal 3: Warm Finance
                proposalCard(
                    title: "🧡 Warm Finance",
                    subtitle: "Friendly • Trustworthy • Organized",
                    description: "Teal and warm amber colors with soft shadows and subtle gradients. Medium rounded corners create an approachable, personal finance app feel.",
                    features: [
                        "Soft elevation shadows",
                        "Subtle background gradients",
                        "Medium corners (16pt)",
                        "Semibold typography"
                    ],
                    colors: [Color.teal, Color.orange, Color.cyan],
                    cornerRadius: 16
                )

                // Implementation note
                VStack(spacing: 12) {
                    Text("Implementation Status")
                        .font(.headline)

                    Text("These are visual mockups showing the three design directions. The full implementation includes design tokens, styled components, and theme switching.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .padding()
        }
        .navigationTitle("UI Proposals")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func proposalCard(
        title: String,
        subtitle: String,
        description: String,
        features: [String],
        colors: [Color],
        cornerRadius: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Color swatches
            HStack(spacing: 8) {
                ForEach(0..<colors.count, id: \.self) { index in
                    Circle()
                        .fill(colors[index])
                        .frame(width: 40, height: 40)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        )
                }

                Spacer()

                // Corner radius indicator
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 40)
                    .overlay(
                        Text("\(Int(cornerRadius))pt")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    )
            }

            Divider()

            // Description
            Text(description)
                .font(.body)
                .foregroundStyle(.primary)

            // Features
            VStack(alignment: .leading, spacing: 8) {
                Text("Key Features:")
                    .font(.subheadline.bold())

                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)

                        Text(feature)
                            .font(.subheadline)
                    }
                }
            }

            // Mock preview card
            VStack(alignment: .leading, spacing: 12) {
                Text("Sample Card Preview")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [colors[0].opacity(0.2), colors[1].opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 100)
                    .overlay(
                        VStack(alignment: .leading) {
                            Text("Invoice Title")
                                .font(.headline)
                            Text("Due: Tomorrow")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("€245.50")
                                .font(.title3.bold())
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .shadow(radius: 8, y: 4)
        )
    }
}

#Preview {
    NavigationStack {
        UIStylePreviewView()
    }
}
