//
//  ContentBlock.swift
//  QuizFlash
//

import SwiftUI
import Foundation

// MARK: - Text Alignment
enum TextBlockAlignment: String, Codable, Equatable {
    case leading, center, trailing

    var alignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }
}

// MARK: - Text Style
enum TextBlockStyle: String, Codable, Equatable {
    case body, title, headline, caption

    var font: Font {
        switch self {
        case .body: return .system(size: 24)
        case .title: return .system(size: 36, weight: .bold)
        case .headline: return .system(size: 26, weight: .semibold)
        case .caption: return .system(size: 16)
        }
    }
}

// MARK: - Font Family
enum FontFamily: String, Codable, Equatable, CaseIterable {
    case system, serif, mono, rounded

    var name: String {
        switch self {
        case .system: return "Sans-Serif"
        case .serif: return "Serif"
        case .mono: return "Monospaced"
        case .rounded: return "Rounded"
        }
    }

    var icon: String {
        switch self {
        case .system: return "textformat"
        case .serif: return "textformat.abc"
        case .mono: return "chevron.left.forwardslash.chevron.right"
        case .rounded: return "a.circle"
        }
    }

    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch self {
        case .system: return .system(size: size, weight: weight)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .mono: return .system(size: size, weight: weight, design: .monospaced)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        }
    }

    func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        switch self {
        case .system: return .systemFont(ofSize: size, weight: weight)
        case .serif: return UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size, weight: weight)
        case .rounded: return UIFont(name: "SF Pro Rounded", size: size) ?? .systemFont(ofSize: size, weight: weight)
        case .mono: return UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }
}

// MARK: - Highlight Color (Marker)
enum HighlightColor: String, Codable, Equatable, CaseIterable {
    case none, yellow, green, pink, cyan, accent

    var color: Color? {
        switch self {
        case .none: return nil
        case .yellow: return Color.yellow.opacity(0.4)
        case .green: return Color.green.opacity(0.35)
        case .pink: return Color.pink.opacity(0.35)
        case .cyan: return Color.cyan.opacity(0.35)
        case .accent: return ThemeManager.shared.accentColor.color
        }
    }

    var name: String {
        switch self {
        case .none: return "None"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .pink: return "Pink"
        case .cyan: return "Cyan"
        case .accent: return "Accent"
        }
    }
}

// MARK: - Text Color
enum TextBlockColor: String, Codable, Equatable, CaseIterable {
    case primary, red, orange, yellow, green, blue, purple

    var color: Color {
        switch self {
        case .primary: return .primary
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        }
    }

    var name: String {
        switch self {
        case .primary: return "Default"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        }
    }
}

extension Alignment {
    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading, .topLeading, .bottomLeading: return .leading
        case .center, .top, .bottom: return .center
        case .trailing, .topTrailing, .bottomTrailing: return .trailing
        default: return .leading
        }
    }
}
