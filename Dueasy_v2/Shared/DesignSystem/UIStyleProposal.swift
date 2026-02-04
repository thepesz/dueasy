import SwiftUI

// MARK: - UI Style Proposal System
//
// PRODUCTION STATUS: App is locked to MIDNIGHT AURORA style.
// Style switching is disabled in production UI but the architecture
// is preserved for future use.
//
// Three dramatically different UI style proposals for DuEasy:
//
// 1. MIDNIGHT AURORA (PRODUCTION) - Dark-first, vibrant gradients, glassmorphism, depth
//    Inspired by: Apple Music, Spotify, premium banking apps
//    Personality: Bold, confident, premium
//
// 2. PAPER MINIMAL (INTERNAL) - Ultra-clean, high contrast, flat design, typographic focus
//    Inspired by: Apple Notes, Things 3, iA Writer
//    Personality: Calm, focused, professional
//
// 3. WARM FINANCE (INTERNAL) - Warm neutrals, subtle textures, card-heavy, approachable
//    Inspired by: Apple Health, Mint, personal finance apps
//    Personality: Friendly, trustworthy, organized
//
// To re-enable style switching:
// 1. Update SettingsManager.uiStyleHome/uiStyleOtherViews to read from UserDefaults
// 2. Add UIStyleSettingsView navigation link in SettingsView
// 3. Update availableStyles array below if exposing more styles

/// The UI styles available in the app.
///
/// **PRODUCTION**: App uses `.midnightAurora` exclusively.
/// Other styles are preserved for internal testing and future expansion.
enum UIStyleProposal: String, Codable, Identifiable {
    /// Current/original app style - warm luxury aesthetic
    case defaultStyle = "default"

    /// Dark-first with vibrant aurora gradients and glass effects
    case midnightAurora = "midnight_aurora"

    /// Ultra-minimal with high contrast and typographic focus (not exposed in picker yet)
    case paperMinimal = "paper_minimal"

    /// Warm neutrals with soft shadows and approachable feel (not exposed in picker yet)
    case warmFinance = "warm_finance"

    var id: String { rawValue }

    /// Only the styles that should appear in the picker
    static var availableStyles: [UIStyleProposal] {
        [.defaultStyle, .midnightAurora]
    }

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .defaultStyle: return "Default"
        case .midnightAurora: return "Midnight Aurora"
        case .paperMinimal: return "Paper Minimal"
        case .warmFinance: return "Warm Finance"
        }
    }

    /// Descriptive tagline for the style
    var tagline: String {
        switch self {
        case .defaultStyle: return "Original warm luxury aesthetic"
        case .midnightAurora: return "Bold gradients, glass depth, premium feel"
        case .paperMinimal: return "Clean, focused, distraction-free"
        case .warmFinance: return "Warm, friendly, organized"
        }
    }

    /// Icon representing the style
    var iconName: String {
        switch self {
        case .defaultStyle: return "circle.fill"
        case .midnightAurora: return "sparkles"
        case .paperMinimal: return "doc.plaintext"
        case .warmFinance: return "heart.text.square"
        }
    }

    /// Preview gradient colors for style picker
    var previewColors: [Color] {
        switch self {
        case .defaultStyle:
            return [
                Color(red: 0.15, green: 0.10, blue: 0.20),
                Color(red: 0.18, green: 0.12, blue: 0.22),
                Color(red: 0.16, green: 0.11, blue: 0.21)
            ]
        case .midnightAurora:
            return [
                Color(red: 0.12, green: 0.12, blue: 0.22),
                Color(red: 0.18, green: 0.10, blue: 0.28),
                Color(red: 0.15, green: 0.15, blue: 0.30)
            ]
        case .paperMinimal:
            return [
                Color(red: 0.98, green: 0.98, blue: 0.98),
                Color(red: 0.95, green: 0.95, blue: 0.95),
                Color(red: 0.92, green: 0.92, blue: 0.92)
            ]
        case .warmFinance:
            return [
                Color(red: 0.98, green: 0.96, blue: 0.93),
                Color(red: 0.96, green: 0.94, blue: 0.90),
                Color(red: 0.94, green: 0.91, blue: 0.86)
            ]
        }
    }
}

/// Context for which view type the style should be applied to
enum UIStyleContext: String, CaseIterable, Identifiable, Codable {
    case home = "home"
    case otherViews = "other_views"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .home: return "Home View"
        case .otherViews: return "Other Views"
        }
    }
}

// MARK: - Style Configuration

/// Holds the user's style preferences for different view contexts.
/// NOTE: Default values are set to .midnightAurora since the app is locked to that style.
struct UIStyleConfiguration: Codable, Equatable {
    var homeStyle: UIStyleProposal
    var otherViewsStyle: UIStyleProposal

    static let `default` = UIStyleConfiguration(
        homeStyle: .midnightAurora,
        otherViewsStyle: .midnightAurora
    )
}

// MARK: - Environment Key

/// Environment key for accessing the current UI style.
/// NOTE: Default value is set to .midnightAurora since the app is now locked to that style.
/// This prevents any flash of default/white background during navigation transitions.
struct UIStyleKey: EnvironmentKey {
    static let defaultValue: UIStyleProposal = .midnightAurora
}

extension EnvironmentValues {
    var uiStyle: UIStyleProposal {
        get { self[UIStyleKey.self] }
        set { self[UIStyleKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    /// Applies the specified UI style to the view hierarchy
    func uiStyle(_ style: UIStyleProposal) -> some View {
        environment(\.uiStyle, style)
    }
}
