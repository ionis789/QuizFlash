//
//  ThemeManager.swift
//  QuizFlash
//
//  Created by Ion Socol on 05.02.2026.
//

import SwiftUI

/// Available accent colors for the app
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
    
    var id: String { rawValue }
    
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
    
    var iconName: String {
        "circle.fill"
    }
}

/// Manager for app-wide theme settings
@Observable
class ThemeManager {
    static let shared = ThemeManager()
    
    private let accentColorKey = "selectedAccentColor"
    
    var accentColor: AccentColorOption {
        didSet {
            UserDefaults.standard.set(accentColor.rawValue, forKey: accentColorKey)
        }
    }
    
    init() {
        if let saved = UserDefaults.standard.string(forKey: accentColorKey),
           let color = AccentColorOption(rawValue: saved) {
            self.accentColor = color
        } else {
            self.accentColor = .blue
        }
    }
}

// MARK: - View Extension for Theme
extension View {
    func themed() -> some View {
        self.tint(ThemeManager.shared.accentColor.color)
    }
}
