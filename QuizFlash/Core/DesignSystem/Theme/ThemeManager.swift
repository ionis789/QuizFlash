//
//  ThemeManager.swift
//  QuizFlash
//
//  Created by Ion Socol on 05.02.2026.
//

import SwiftUI

// MARK: - Accent Color Options

/// Defines the available accent colors for the application's theme.
enum AccentColorOption: String, CaseIterable, Identifiable {
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case mint = "Mint"
    case teal = "Teal"
    case cyan = "Cyan"
    
    /// The unique identifier for the color option.
    var id: String { rawValue }
    
    /// The SwiftUI `Color` associated with this option.
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        }
    }
    
    /// The SF Symbol icon name representing this color option in the UI.
    var iconName: String {
        "circle.fill"
    }
}

// MARK: - Theme Manager

/// A global state manager responsible for handling the application's visual theme,
/// including the user's preferred accent color.
///
/// This class uses the `@Observable` macro for seamless SwiftUI integration (iOS 17+).
@Observable
final class ThemeManager {
    
    /// The shared singleton instance.
    static let shared = ThemeManager()
    
    /// The UserDefaults key used for persisting the accent color.
    private let accentColorKey = "selectedAccentColor"
    
    /// The currently selected accent color.
    /// Modifying this property automatically updates the UI and persists the choice to `UserDefaults`.
    var accentColor: AccentColorOption {
        didSet {
            UserDefaults.standard.set(accentColor.rawValue, forKey: accentColorKey)
        }
    }
    
    /// Initializes the `ThemeManager`, restoring the saved color from `UserDefaults` if available.
    private init() {
        if let savedValue = UserDefaults.standard.string(forKey: accentColorKey),
           let savedColor = AccentColorOption(rawValue: savedValue) {
            self.accentColor = savedColor
        } else {
            self.accentColor = .blue
        }
    }
}
