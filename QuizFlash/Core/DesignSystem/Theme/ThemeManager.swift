//
//  ThemeManager.swift
//  QuizFlash
//
//  Manages the application-wide visual theme, including the user's accent colour selection.
//

import SwiftUI

enum AppScreenBackgroundStyle {
    case primary
    case grouped
}

// MARK: - Accent Color Option

/// Defines the available accent colours for the application's theme.
enum AccentColorOption: String, CaseIterable, Identifiable {
    case blue   = "Blue"
    case purple = "Purple"
    case pink   = "Pink"
    case red    = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green  = "Green"
    case mint   = "Mint"
    case teal   = "Teal"
    case cyan   = "Cyan"

    // MARK: - Identifiable

    /// The unique identifier for this colour option (equals its raw value).
    var id: String { rawValue }

    // MARK: - Presentation

    /// The SwiftUI `Color` associated with this option.
    var color: Color {
        switch self {
        case .blue:   return .blue
        case .purple: return .purple
        case .pink:   return .pink
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .mint:   return .mint
        case .teal:   return .teal
        case .cyan:   return .cyan
        }
    }

    /// The SF Symbol icon name used to represent this colour option in the settings UI.
    var iconName: String { "circle.fill" }
}

// MARK: - Theme Manager

/// A global state manager responsible for the application's visual theme.
///
/// Use `ThemeManager.shared` to read or change the current accent colour.
/// The selected colour is persisted to `UserDefaults` and restored on next launch.
///
/// Inject the shared instance into the SwiftUI environment at the root level so
/// all child views can observe accent colour changes reactively:
/// ```swift
/// .environment(ThemeManager.shared)
/// ```
@Observable
final class ThemeManager {

    // MARK: - Singleton

    /// The application-wide shared instance.
    static let shared = ThemeManager()

    // MARK: - Persistence

    /// The `UserDefaults` key used to persist the selected accent colour across launches.
    private let accentColorKey = "selectedAccentColor"

    // MARK: - Properties

    /// The currently selected accent colour.
    ///
    /// Setting this property automatically persists the new value to `UserDefaults`
    /// via the `didSet` observer and propagates the change to all observing views.
    var accentColor: AccentColorOption {
        didSet {
            UserDefaults.standard.set(accentColor.rawValue, forKey: accentColorKey)
        }
    }

    var screenBackground: Color {
        .black
    }

    var groupedScreenBackground: Color {
        .black
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

    /// Restores the last saved accent colour from `UserDefaults`, falling back to `.blue`.
    private init() {
        if let savedValue = UserDefaults.standard.string(forKey: accentColorKey),
           let savedColor = AccentColorOption(rawValue: savedValue) {
            self.accentColor = savedColor
        } else {
            self.accentColor = .blue
        }
    }
}
