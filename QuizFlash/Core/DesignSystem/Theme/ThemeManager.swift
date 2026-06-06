//
//  ThemeManager.swift
//  QuizFlash
//
//  Manages the application-wide visual theme and fixed brand palette.
//

import SwiftUI

enum AppScreenBackgroundStyle {
    case primary
    case grouped
}

// MARK: - Theme Color Tokens

/// Semantic color tokens that can be overridden live in development.
enum ThemeColorTokenGroup: String, CaseIterable, Identifiable {
    case backgrounds = "Backgrounds"
    case surfaces = "Surfaces"
    case brand = "Brand"
    case content = "Content"
    case feedback = "Feedback"

    var id: String { rawValue }
}

/// Describes a concrete app surface where a semantic theme role is visible.
struct ThemeStudioUsageReference: Hashable, Identifiable {
    let title: String
    let detail: String

    var id: String { "\(title)|\(detail)" }
}

/// High-level preview families used by Theme Studio to render the role in context.
enum ThemeStudioRolePreviewKind {
    case tintAccent
    case screen
    case primaryButton
    case secondaryButton
    case dangerButton
    case surfaceButton
    case primaryLabel
    case secondaryLabel
    case dangerLabel
    case surfaceLabel
    case cardSurface
    case widgetSurface
    case tabBar
    case circularToolbar
    case backCapsule
}

/// Semantic theme tokens that back the app's shared palette.
enum ThemeColorToken: String, CaseIterable, Identifiable {
    case backgroundPrimary = "BackgroundPrimary"
    case backgroundSecondary = "BackgroundSecondary"
    case surfacePrimary = "SurfacePrimary"
    case surfaceSecondary = "SurfaceSecondary"
    case brandPrimary = "BrandPrimary"
    case brandStrong = "BrandStrong"
    case brandDeep = "BrandDeep"
    case textPrimary = "TextPrimary"
    case textSecondary = "TextSecondary"
    case highlightWarm = "HighlightWarm"
    case highlightRose = "HighlightRose"
    case successPrimary = "SuccessPrimary"
    case dangerPrimary = "DangerPrimary"

    var id: String { rawValue }

    var assetName: String { rawValue }

    var title: String {
        switch self {
        case .backgroundPrimary: "Background Primary"
        case .backgroundSecondary: "Background Secondary"
        case .surfacePrimary: "Surface Primary"
        case .surfaceSecondary: "Surface Secondary"
        case .brandPrimary: "Brand Primary"
        case .brandStrong: "Brand Strong"
        case .brandDeep: "Brand Deep"
        case .textPrimary: "Text Primary"
        case .textSecondary: "Text Secondary"
        case .highlightWarm: "Highlight Warm"
        case .highlightRose: "Highlight Rose"
        case .successPrimary: "Success Primary"
        case .dangerPrimary: "Danger Primary"
        }
    }

    var usage: String {
        switch self {
        case .backgroundPrimary:
            "App shell and full-screen backgrounds."
        case .backgroundSecondary:
            "Grouped pages and nested surfaces."
        case .surfacePrimary:
            "Widgets, cards, and neutral content surfaces."
        case .surfaceSecondary:
            "Toolbars, floating chrome, and secondary elevated controls."
        case .brandPrimary:
            "Primary purple accents and selected states."
        case .brandStrong:
            "Dense purple fills such as selected capsules."
        case .brandDeep:
            "Dark plum used behind light content."
        case .textPrimary:
            "Primary foreground on dark surfaces."
        case .textSecondary:
            "Secondary labels and subdued content."
        case .highlightWarm:
            "Warm highlight surfaces and soft emphasis."
        case .highlightRose:
            "Soft rose surfaces behind red emphasis."
        case .successPrimary:
            "Fresh green accents and positive directional feedback."
        case .dangerPrimary:
            "Strong red accents and high-priority actions."
        }
    }

    var group: ThemeColorTokenGroup {
        switch self {
        case .backgroundPrimary, .backgroundSecondary:
            .backgrounds
        case .surfacePrimary, .surfaceSecondary:
            .surfaces
        case .brandPrimary, .brandStrong, .brandDeep:
            .brand
        case .textPrimary, .textSecondary:
            .content
        case .highlightWarm, .highlightRose, .successPrimary, .dangerPrimary:
            .feedback
        }
    }
}

// MARK: - Theme UI Roles

/// Groups UI-facing color roles by where they are used in the product.
enum ThemeColorRoleGroup: String, CaseIterable, Identifiable {
    case shell = "Shell"
    case buttons = "Buttons"
    case labels = "Labels"
    case surfaces = "Surfaces"
    case navigation = "Navigation"

    var id: String { rawValue }
}

/// Semantic UI roles that map views to palette tokens.
///
/// Tokens answer "what colors exist in the palette".
/// Roles answer "which color does this part of the UI use".
enum ThemeColorRole: String, CaseIterable, Identifiable {
    case tintAccent = "TintAccent"
    case screenBackgroundPrimary = "ScreenBackgroundPrimary"
    case screenBackgroundGrouped = "ScreenBackgroundGrouped"

    case buttonPrimaryFill = "ButtonPrimaryFill"
    case buttonPrimaryForeground = "ButtonPrimaryForeground"
    case buttonSecondaryFill = "ButtonSecondaryFill"
    case buttonSecondaryForeground = "ButtonSecondaryForeground"
    case buttonDangerFill = "ButtonDangerFill"
    case buttonDangerForeground = "ButtonDangerForeground"
    case buttonSurfaceFill = "ButtonSurfaceFill"
    case buttonSurfaceForeground = "ButtonSurfaceForeground"

    case labelPrimaryFill = "LabelPrimaryFill"
    case labelPrimaryForeground = "LabelPrimaryForeground"
    case labelSecondaryFill = "LabelSecondaryFill"
    case labelSecondaryForeground = "LabelSecondaryForeground"
    case labelDangerFill = "LabelDangerFill"
    case labelDangerForeground = "LabelDangerForeground"
    case labelSurfaceFill = "LabelSurfaceFill"
    case labelSurfaceForeground = "LabelSurfaceForeground"

    case cardSurfaceFill = "CardSurfaceFill"
    case widgetSurfaceFill = "WidgetSurfaceFill"
    case settingsCardFill = "SettingsCardFill"
    case settingsCardBorder = "SettingsCardBorder"
    case selectionToolbarFill = "SelectionToolbarFill"
    case selectionToolbarBorder = "SelectionToolbarBorder"

    case tabBarTrackFill = "TabBarTrackFill"
    case tabSelectionFill = "TabSelectionFill"
    case tabSelectionForeground = "TabSelectionForeground"
    case tabUnselectedForeground = "TabUnselectedForeground"

    case circularToolbarFill = "CircularToolbarFill"
    case circularToolbarForeground = "CircularToolbarForeground"
    case backButtonForeground = "BackButtonForeground"

    var id: String { rawValue }

    var isFixedScreenBackground: Bool {
        switch self {
        case .screenBackgroundPrimary, .screenBackgroundGrouped:
            true
        default:
            false
        }
    }

    var title: String {
        switch self {
        case .tintAccent: "Tint Accent"
        case .screenBackgroundPrimary: "Primary Screen Background"
        case .screenBackgroundGrouped: "Grouped Screen Background"
        case .buttonPrimaryFill: "Primary Button Fill"
        case .buttonPrimaryForeground: "Primary Button Text"
        case .buttonSecondaryFill: "Secondary Button Fill"
        case .buttonSecondaryForeground: "Secondary Button Text"
        case .buttonDangerFill: "Danger Button Fill"
        case .buttonDangerForeground: "Danger Button Text"
        case .buttonSurfaceFill: "Surface Button Fill"
        case .buttonSurfaceForeground: "Surface Button Text"
        case .labelPrimaryFill: "Primary Label Fill"
        case .labelPrimaryForeground: "Primary Label Text"
        case .labelSecondaryFill: "Secondary Label Fill"
        case .labelSecondaryForeground: "Secondary Label Text"
        case .labelDangerFill: "Danger Label Fill"
        case .labelDangerForeground: "Danger Label Text"
        case .labelSurfaceFill: "Surface Label Fill"
        case .labelSurfaceForeground: "Surface Label Text"
        case .cardSurfaceFill: "Card Surface Fill"
        case .widgetSurfaceFill: "Widget Surface Fill"
        case .settingsCardFill: "Settings Card Fill"
        case .settingsCardBorder: "Settings Card Border"
        case .selectionToolbarFill: "Selection Toolbar Fill"
        case .selectionToolbarBorder: "Selection Toolbar Border"
        case .tabBarTrackFill: "Tab Bar Track Fill"
        case .tabSelectionFill: "Tab Selection Fill"
        case .tabSelectionForeground: "Tab Selection Text"
        case .tabUnselectedForeground: "Tab Unselected Text"
        case .circularToolbarFill: "Circular Toolbar Fill"
        case .circularToolbarForeground: "Circular Toolbar Icon"
        case .backButtonForeground: "Back Button Text"
        }
    }

    var usage: String {
        switch self {
        case .tintAccent:
            "Global SwiftUI tint used by system controls."
        case .screenBackgroundPrimary:
            "Main full-screen background for the app shell."
        case .screenBackgroundGrouped:
            "Nested or grouped screen background."
        case .buttonPrimaryFill:
            "Primary CTA background."
        case .buttonPrimaryForeground:
            "Primary CTA text and icon color."
        case .buttonSecondaryFill:
            "Light CTA background."
        case .buttonSecondaryForeground:
            "Light CTA text and icon color."
        case .buttonDangerFill:
            "High-priority CTA background."
        case .buttonDangerForeground:
            "High-priority CTA text and icon color."
        case .buttonSurfaceFill:
            "Neutral action button background."
        case .buttonSurfaceForeground:
            "Neutral action button text and icon color."
        case .labelPrimaryFill:
            "Filled pill or tag background."
        case .labelPrimaryForeground:
            "Filled pill or tag text color."
        case .labelSecondaryFill:
            "Light pill or badge background."
        case .labelSecondaryForeground:
            "Light pill or badge text color."
        case .labelDangerFill:
            "Danger pill or badge background."
        case .labelDangerForeground:
            "Danger pill or badge text color."
        case .labelSurfaceFill:
            "Neutral pill or capsule background."
        case .labelSurfaceForeground:
            "Neutral pill or capsule text color."
        case .cardSurfaceFill:
            "Elevated card-style surfaces."
        case .widgetSurfaceFill:
            "Widget blocks and content modules."
        case .settingsCardFill:
            "Grouped settings card background."
        case .settingsCardBorder:
            "Grouped settings card border and dividers."
        case .selectionToolbarFill:
            "Selection toolbar cluster background."
        case .selectionToolbarBorder:
            "Selection toolbar cluster border."
        case .tabBarTrackFill:
            "Floating tab bar container."
        case .tabSelectionFill:
            "Selected tab capsule fill."
        case .tabSelectionForeground:
            "Selected tab icon and text."
        case .tabUnselectedForeground:
            "Unselected tab icon and text."
        case .circularToolbarFill:
            "Round top-bar button background."
        case .circularToolbarForeground:
            "Round top-bar button icon color."
        case .backButtonForeground:
            "Back capsule text and icon color."
        }
    }

    var usageReferences: [ThemeStudioUsageReference] {
        switch self {
        case .tintAccent:
            [
                ThemeStudioUsageReference(title: "System controls", detail: "Toggles, links, pickers, and segmented controls."),
                ThemeStudioUsageReference(title: "Editor affordances", detail: "Formatting highlights and accent-driven interactions.")
            ]
        case .screenBackgroundPrimary:
            [
                ThemeStudioUsageReference(title: "Main app shell", detail: "Home, Library, Deck, Create, and Labs root screens."),
                ThemeStudioUsageReference(title: "Large scrolling surfaces", detail: "The dark canvas behind cards, lists, and floating chrome.")
            ]
        case .screenBackgroundGrouped:
            [
                ThemeStudioUsageReference(title: "Grouped settings pages", detail: "Nested settings and detail screens."),
                ThemeStudioUsageReference(title: "Secondary shells", detail: "Use when a pushed screen needs softer separation from the app shell.")
            ]
        case .buttonPrimaryFill, .buttonPrimaryForeground:
            [
                ThemeStudioUsageReference(title: "Primary CTA buttons", detail: "Dashboard actions and important confirm actions."),
                ThemeStudioUsageReference(title: "Selected intent", detail: "Buttons meant to read as the app's main affirmative action.")
            ]
        case .buttonSecondaryFill, .buttonSecondaryForeground:
            [
                ThemeStudioUsageReference(title: "Light utility actions", detail: "Small secondary buttons like clear or dismiss helpers."),
                ThemeStudioUsageReference(title: "Inline accessory actions", detail: "Supportive actions that should stay lighter than the primary CTA.")
            ]
        case .buttonDangerFill, .buttonDangerForeground:
            [
                ThemeStudioUsageReference(title: "Destructive actions", detail: "Delete, clear, remove, and warning-weight controls."),
                ThemeStudioUsageReference(title: "Deck management", detail: "Danger buttons inside deck detail and workspace flows.")
            ]
        case .buttonSurfaceFill, .buttonSurfaceForeground:
            [
                ThemeStudioUsageReference(title: "Floating chrome actions", detail: "Round and capsule buttons in Library, Deck, and Home top bars."),
                ThemeStudioUsageReference(title: "Neutral action controls", detail: "Buttons that should read as glassy utility chrome rather than CTA.")
            ]
        case .labelPrimaryFill, .labelPrimaryForeground:
            [
                ThemeStudioUsageReference(title: "Selected pills", detail: "Highlighted state chips, active filters, and selected capsules."),
                ThemeStudioUsageReference(title: "Stat accents", detail: "Primary value badges and dense emphasis labels.")
            ]
        case .labelSecondaryFill, .labelSecondaryForeground:
            [
                ThemeStudioUsageReference(title: "Supportive pills", detail: "Light tags and secondary metadata chips."),
                ThemeStudioUsageReference(title: "Quiet selection states", detail: "Less dominant badges that still need separation from the background.")
            ]
        case .labelDangerFill, .labelDangerForeground:
            [
                ThemeStudioUsageReference(title: "Warning chips", detail: "Destructive or overdue labels and warning emphasis states."),
                ThemeStudioUsageReference(title: "Alert metadata", detail: "Badges that need to read as risky without becoming full buttons.")
            ]
        case .labelSurfaceFill, .labelSurfaceForeground:
            [
                ThemeStudioUsageReference(title: "Neutral capsules", detail: "Inline count chips and toolbar labels."),
                ThemeStudioUsageReference(title: "Surface metadata", detail: "Badges that should blend into floating chrome and cards.")
            ]
        case .cardSurfaceFill:
            [
                ThemeStudioUsageReference(title: "Flashcard faces", detail: "Full card surfaces used in study and preview modes."),
                ThemeStudioUsageReference(title: "Large card treatments", detail: "Surfaces that need stronger border and depth than widgets.")
            ]
        case .widgetSurfaceFill:
            [
                ThemeStudioUsageReference(title: "Dashboard cards", detail: "Home stats, recent decks, folders, and overview widgets."),
                ThemeStudioUsageReference(title: "Shared modules", detail: "Rows and panels that use flashcardStyle(.widget).")
            ]
        case .settingsCardFill, .settingsCardBorder:
            [
                ThemeStudioUsageReference(title: "Settings cards", detail: "SettingsHeaderCard, SettingsSectionCard, and SettingsInfoCard."),
                ThemeStudioUsageReference(title: "Grouped settings chrome", detail: "Reusable card surfaces across Settings and pushed settings screens.")
            ]
        case .selectionToolbarFill, .selectionToolbarBorder:
            [
                ThemeStudioUsageReference(title: "Library selection toolbar", detail: "Bottom multi-select action cluster in Library."),
                ThemeStudioUsageReference(title: "Contextual action chrome", detail: "Dense bottom toolbar surfaces that appear during selection states.")
            ]
        case .tabBarTrackFill:
            [
                ThemeStudioUsageReference(title: "Bottom chrome", detail: "Floating custom tab bar track across the whole app."),
                ThemeStudioUsageReference(title: "Persistent navigation shell", detail: "The glass-like base behind tab items.")
            ]
        case .tabSelectionFill, .tabSelectionForeground:
            [
                ThemeStudioUsageReference(title: "Selected tab capsule", detail: "Active tab indicator in the floating tab bar."),
                ThemeStudioUsageReference(title: "Primary navigation focus", detail: "The strongest persistent navigation accent in the app.")
            ]
        case .tabUnselectedForeground:
            [
                ThemeStudioUsageReference(title: "Inactive tabs", detail: "Unselected tab icons and labels in the bottom chrome."),
                ThemeStudioUsageReference(title: "Resting navigation state", detail: "Default navigation text/icon color when not selected.")
            ]
        case .circularToolbarFill, .circularToolbarForeground:
            [
                ThemeStudioUsageReference(title: "Top circular buttons", detail: "Library, Home calendar, and Deck floating toolbar actions."),
                ThemeStudioUsageReference(title: "Search and more controls", detail: "Round chrome that must stay crisp over the blur layer.")
            ]
        case .backButtonForeground:
            [
                ThemeStudioUsageReference(title: "Back capsules", detail: "Pill back buttons in Library, Deck, and pushed settings screens."),
                ThemeStudioUsageReference(title: "Contextual navigation", detail: "The left-aligned escape action in custom top chrome.")
            ]
        }
    }

    var previewKind: ThemeStudioRolePreviewKind {
        switch self {
        case .tintAccent:
            .tintAccent
        case .screenBackgroundPrimary, .screenBackgroundGrouped:
            .screen
        case .buttonPrimaryFill, .buttonPrimaryForeground:
            .primaryButton
        case .buttonSecondaryFill, .buttonSecondaryForeground:
            .secondaryButton
        case .buttonDangerFill, .buttonDangerForeground:
            .dangerButton
        case .buttonSurfaceFill, .buttonSurfaceForeground:
            .surfaceButton
        case .labelPrimaryFill, .labelPrimaryForeground:
            .primaryLabel
        case .labelSecondaryFill, .labelSecondaryForeground:
            .secondaryLabel
        case .labelDangerFill, .labelDangerForeground:
            .dangerLabel
        case .labelSurfaceFill, .labelSurfaceForeground:
            .surfaceLabel
        case .cardSurfaceFill:
            .cardSurface
        case .widgetSurfaceFill:
            .widgetSurface
        case .settingsCardFill, .settingsCardBorder, .selectionToolbarFill, .selectionToolbarBorder:
            .widgetSurface
        case .tabBarTrackFill,
             .tabSelectionFill,
             .tabSelectionForeground,
             .tabUnselectedForeground:
            .tabBar
        case .circularToolbarFill, .circularToolbarForeground:
            .circularToolbar
        case .backButtonForeground:
            .backCapsule
        }
    }

    var studioStatusNote: String? {
        switch self {
        case .circularToolbarFill:
            "This role is defined, but the current circular chrome still inherits its fill from Surface Button Fill. Changing it won't affect the live UI until that wiring is migrated."
        case .tabSelectionForeground:
            "The live tab bar keeps selected tab text and icon on the fixed brand purple for readability. This role remains available for previews and future navigation surfaces."
        default:
            nil
        }
    }

    var group: ThemeColorRoleGroup {
        switch self {
        case .tintAccent, .screenBackgroundPrimary, .screenBackgroundGrouped:
            .shell
        case .buttonPrimaryFill,
             .buttonPrimaryForeground,
             .buttonSecondaryFill,
             .buttonSecondaryForeground,
             .buttonDangerFill,
             .buttonDangerForeground,
             .buttonSurfaceFill,
             .buttonSurfaceForeground:
            .buttons
        case .labelPrimaryFill,
             .labelPrimaryForeground,
             .labelSecondaryFill,
             .labelSecondaryForeground,
             .labelDangerFill,
             .labelDangerForeground,
             .labelSurfaceFill,
             .labelSurfaceForeground:
            .labels
        case .cardSurfaceFill, .widgetSurfaceFill:
            .surfaces
        case .settingsCardFill, .settingsCardBorder, .selectionToolbarFill, .selectionToolbarBorder:
            .surfaces
        case .tabBarTrackFill,
             .tabSelectionFill,
             .tabSelectionForeground,
             .tabUnselectedForeground,
             .circularToolbarFill,
             .circularToolbarForeground,
             .backButtonForeground:
            .navigation
        }
    }

    var defaultToken: ThemeColorToken {
        switch self {
        case .tintAccent: .brandPrimary
        case .screenBackgroundPrimary: .backgroundPrimary
        case .screenBackgroundGrouped: .backgroundPrimary
        case .buttonPrimaryFill: .brandPrimary
        case .buttonPrimaryForeground: .brandDeep
        case .buttonSecondaryFill: .highlightWarm
        case .buttonSecondaryForeground: .brandDeep
        case .buttonDangerFill: .highlightRose
        case .buttonDangerForeground: .dangerPrimary
        case .buttonSurfaceFill: .surfaceSecondary
        case .buttonSurfaceForeground: .textPrimary
        case .labelPrimaryFill: .brandPrimary
        case .labelPrimaryForeground: .brandDeep
        case .labelSecondaryFill: .highlightWarm
        case .labelSecondaryForeground: .brandDeep
        case .labelDangerFill: .highlightRose
        case .labelDangerForeground: .dangerPrimary
        case .labelSurfaceFill: .surfaceSecondary
        case .labelSurfaceForeground: .textPrimary
        case .cardSurfaceFill: .surfaceSecondary
        case .widgetSurfaceFill: .surfacePrimary
        case .settingsCardFill: .surfacePrimary
        case .settingsCardBorder: .textPrimary
        case .selectionToolbarFill: .surfaceSecondary
        case .selectionToolbarBorder: .textPrimary
        case .tabBarTrackFill: .backgroundSecondary
        case .tabSelectionFill: .surfaceSecondary
        case .tabSelectionForeground: .brandPrimary
        case .tabUnselectedForeground: .textPrimary
        case .circularToolbarFill: .brandStrong
        case .circularToolbarForeground: .brandPrimary
        case .backButtonForeground: .brandPrimary
        }
    }
}

// MARK: - Accent Color Option

/// Defines the fixed brand accent used by the application's theme.
enum AccentColorOption: String, CaseIterable, Identifiable {
    case brand = "Lavender"

    // MARK: - Identifiable

    /// The unique identifier for this colour option (equals its raw value).
    var id: String { rawValue }

    // MARK: - Presentation

    /// The SwiftUI `Color` associated with the fixed brand accent.
    var color: Color {
        ThemeManager.shared.roleColor(.tintAccent)
    }

    /// The SF Symbol icon name used to represent this colour option in the settings UI.
    var iconName: String { "circle.fill" }
}

// MARK: - Theme Manager

/// A global state manager responsible for the application's fixed visual theme.
///
/// Inject the shared instance into the SwiftUI environment at the root level so
/// all child views can resolve semantic palette values consistently:
/// ```swift
/// .environment(ThemeManager.shared)
/// ```
@Observable
final class ThemeManager {

    private enum Keys {
        static let colorOverrides = "preferences.development.themeColorOverrides"
        static let roleOverrides = "preferences.development.themeRoleOverrides"
    }

    // MARK: - Singleton

    /// The application-wide shared instance.
    static let shared = ThemeManager()

    // MARK: - Properties

    private let userDefaults: UserDefaults
    private var colorOverrideHexes: [String: String]
    private var roleOverrideTokenNames: [String: String]

    /// The application's fixed accent colour.
    var accentColor: AccentColorOption {
        .brand
    }

    func roleColor(_ role: ThemeColorRole) -> Color {
        color(resolvedToken(for: role))
    }

    func rolesResolving(to token: ThemeColorToken) -> [ThemeColorRole] {
        ThemeColorRole.allCases.filter { resolvedToken(for: $0) == token }
    }

    func usageReferences(for token: ThemeColorToken) -> [ThemeStudioUsageReference] {
        let roles = rolesResolving(to: token)
        var seen = Set<String>()
        var ordered: [ThemeStudioUsageReference] = []

        for reference in roles.flatMap(\.usageReferences) {
            if seen.insert(reference.id).inserted {
                ordered.append(reference)
            }
        }

        return ordered
    }

    func resolvedToken(for role: ThemeColorRole) -> ThemeColorToken {
        if role.isFixedScreenBackground {
            return .backgroundPrimary
        }

        if let rawValue = roleOverrideTokenNames[role.rawValue],
           let token = ThemeColorToken(rawValue: rawValue) {
            return token
        }

        return role.defaultToken
    }

    func hasRoleOverride(for role: ThemeColorRole) -> Bool {
        roleOverrideTokenNames[role.rawValue] != nil
    }

    var hasRoleOverrides: Bool {
        !roleOverrideTokenNames.isEmpty
    }

    var hasThemeOverrides: Bool {
        hasColorOverrides || hasRoleOverrides
    }

    func setRoleOverride(_ token: ThemeColorToken, for role: ThemeColorRole) {
        guard !role.isFixedScreenBackground else {
            clearRoleOverride(for: role)
            return
        }

        roleOverrideTokenNames[role.rawValue] = token.rawValue
        persistOverrides()
    }

    func clearRoleOverride(for role: ThemeColorRole) {
        roleOverrideTokenNames.removeValue(forKey: role.rawValue)
        persistOverrides()
    }

    func resetAllRoleOverrides() {
        roleOverrideTokenNames.removeAll()
        persistOverrides()
    }

    func resetAllThemeOverrides() {
        colorOverrideHexes.removeAll()
        roleOverrideTokenNames.removeAll()
        persistOverrides()
    }

    func color(_ token: ThemeColorToken) -> Color {
        if token == .backgroundPrimary {
            return .black
        }

        if let overrideHex = colorOverrideHexes[token.rawValue],
           let overrideColor = Color(hex: overrideHex) {
            return overrideColor
        }

        return Color(token.assetName)
    }

    func resolvedHex(for token: ThemeColorToken) -> String {
        if token == .backgroundPrimary {
            return "#000000"
        }

        if let overrideHex = colorOverrideHexes[token.rawValue] {
            return overrideHex
        }

        return color(token).toHex() ?? "#000000"
    }

    func defaultHex(for token: ThemeColorToken) -> String {
        Color(token.assetName).toHex() ?? "#000000"
    }

    func hasColorOverride(for token: ThemeColorToken) -> Bool {
        if token == .backgroundPrimary {
            return false
        }

        return colorOverrideHexes[token.rawValue] != nil
    }

    var hasColorOverrides: Bool {
        !colorOverrideHexes.isEmpty
    }

    func setColorOverride(_ color: Color, for token: ThemeColorToken) {
        guard let hex = color.toHex() else { return }
        setColorHexOverride(hex, for: token)
    }

    func setColorHexOverride(_ hex: String, for token: ThemeColorToken) {
        guard token != .backgroundPrimary else {
            clearColorOverride(for: token)
            return
        }

        guard let normalizedHex = Self.normalizedHex(hex),
              Color(hex: normalizedHex) != nil else { return }

        colorOverrideHexes[token.rawValue] = normalizedHex
        persistOverrides()
    }

    func clearColorOverride(for token: ThemeColorToken) {
        colorOverrideHexes.removeValue(forKey: token.rawValue)
        persistOverrides()
    }

    func resetAllColorOverrides() {
        colorOverrideHexes.removeAll()
        persistOverrides()
    }

    var brandPrimary: Color {
        color(.brandPrimary)
    }

    var brandStrong: Color {
        color(.brandStrong)
    }

    var brandDeep: Color {
        color(.brandDeep)
    }

    var textPrimary: Color {
        color(.textPrimary)
    }

    var textSecondary: Color {
        color(.textSecondary)
    }

    var surfacePrimary: Color {
        color(.surfacePrimary)
    }

    var surfaceSecondary: Color {
        color(.surfaceSecondary)
    }

    var backgroundSecondary: Color {
        color(.backgroundSecondary)
    }

    var highlightWarm: Color {
        color(.highlightWarm)
    }

    var highlightRose: Color {
        color(.highlightRose)
    }

    var successPrimary: Color {
        color(.successPrimary)
    }

    var dangerPrimary: Color {
        color(.dangerPrimary)
    }

    var screenBackground: Color {
        roleColor(.screenBackgroundPrimary)
    }

    var groupedScreenBackground: Color {
        roleColor(.screenBackgroundGrouped)
    }

    func backgroundColor(for style: AppScreenBackgroundStyle) -> Color {
        switch style {
        case .primary:
            screenBackground
        case .grouped:
            groupedScreenBackground
        }
    }

    // MARK: - Initializer

    /// Maintains API compatibility for call sites that still inject a local defaults store.
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.colorOverrideHexes = userDefaults.dictionary(forKey: Keys.colorOverrides) as? [String: String] ?? [:]
        self.roleOverrideTokenNames = userDefaults.dictionary(forKey: Keys.roleOverrides) as? [String: String] ?? [:]
        enforceFixedScreenBackgroundIfNeeded()
        migrateLegacySurfaceTokenIfNeeded()
        migrateLegacyDangerRoleOverridesIfNeeded()
    }

    private func persistOverrides() {
        if colorOverrideHexes.isEmpty {
            userDefaults.removeObject(forKey: Keys.colorOverrides)
        } else {
            userDefaults.set(colorOverrideHexes, forKey: Keys.colorOverrides)
        }

        if roleOverrideTokenNames.isEmpty {
            userDefaults.removeObject(forKey: Keys.roleOverrides)
        } else {
            userDefaults.set(roleOverrideTokenNames, forKey: Keys.roleOverrides)
        }
    }

    private func enforceFixedScreenBackgroundIfNeeded() {
        var didChange = false

        if colorOverrideHexes.removeValue(forKey: ThemeColorToken.backgroundPrimary.rawValue) != nil {
            didChange = true
        }

        for role in ThemeColorRole.allCases where role.isFixedScreenBackground {
            if roleOverrideTokenNames.removeValue(forKey: role.rawValue) != nil {
                didChange = true
            }
        }

        if didChange {
            persistOverrides()
        }
    }

    private func migrateLegacyDangerRoleOverridesIfNeeded() {
        var didChange = false

        if roleOverrideTokenNames[ThemeColorRole.buttonDangerFill.rawValue] == ThemeColorToken.dangerPrimary.rawValue {
            roleOverrideTokenNames[ThemeColorRole.buttonDangerFill.rawValue] = ThemeColorToken.highlightRose.rawValue
            didChange = true
        }

        if roleOverrideTokenNames[ThemeColorRole.buttonDangerForeground.rawValue] == ThemeColorToken.textPrimary.rawValue {
            roleOverrideTokenNames[ThemeColorRole.buttonDangerForeground.rawValue] = ThemeColorToken.dangerPrimary.rawValue
            didChange = true
        }

        if roleOverrideTokenNames[ThemeColorRole.labelDangerFill.rawValue] == ThemeColorToken.dangerPrimary.rawValue {
            roleOverrideTokenNames[ThemeColorRole.labelDangerFill.rawValue] = ThemeColorToken.highlightRose.rawValue
            didChange = true
        }

        if roleOverrideTokenNames[ThemeColorRole.screenBackgroundGrouped.rawValue] == ThemeColorToken.backgroundSecondary.rawValue {
            roleOverrideTokenNames[ThemeColorRole.screenBackgroundGrouped.rawValue] = ThemeColorToken.backgroundPrimary.rawValue
            didChange = true
        }

        if didChange {
            persistOverrides()
        }
    }

    private func migrateLegacySurfaceTokenIfNeeded() {
        let legacyToken = "SurfaceElevated"
        let currentToken = ThemeColorToken.surfaceSecondary.rawValue
        var didChange = false

        if let legacyColorOverride = colorOverrideHexes.removeValue(forKey: legacyToken) {
            if colorOverrideHexes[currentToken] == nil {
                colorOverrideHexes[currentToken] = legacyColorOverride
            }
            didChange = true
        }

        for (role, tokenName) in roleOverrideTokenNames {
            guard tokenName == legacyToken else { continue }
            roleOverrideTokenNames[role] = currentToken
            didChange = true
        }

        if didChange {
            persistOverrides()
        }
    }

    private static func normalizedHex(_ input: String) -> String? {
        let trimmed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "#", with: "")

        guard trimmed.count == 6 || trimmed.count == 8 else { return nil }
        guard CharacterSet(charactersIn: trimmed).isSubset(of: CharacterSet(charactersIn: "0123456789ABCDEF")) else {
            return nil
        }

        return "#\(trimmed)"
    }
}
