//
//  ContentBlock.swift
//  QuizFlash
//

import SwiftUI
import Foundation
import UIKit

// MARK: - Forced Line Break

enum ZoneForcedLineBreak {
    nonisolated static let marker = "┃"

    nonisolated static func renderText(_ text: String) -> String {
        normalizeCarriageReturns(in: text)
            .replacingOccurrences(of: marker, with: "\n")
    }

    nonisolated static func normalizeCarriageReturns(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func applyMarkerStyle(
        to textStorage: NSTextStorage,
        baseAttributes: [NSAttributedString.Key: Any],
        markerColor: UIColor
    ) {
        let fullText = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: fullText.length)
        guard fullRange.length > 0 else { return }

        var searchRange = fullRange
        while searchRange.length > 0 {
            let markerRange = fullText.range(of: marker, options: [], range: searchRange)
            guard markerRange.location != NSNotFound else { break }

            var attributes = baseAttributes
            attributes[.foregroundColor] = markerColor
            attributes[.font] = markerFont(from: baseAttributes[.font] as? UIFont)
            textStorage.setAttributes(attributes, range: markerRange)

            let nextLocation = markerRange.location + markerRange.length
            let end = fullRange.location + fullRange.length
            searchRange = NSRange(location: nextLocation, length: max(end - nextLocation, 0))
        }
    }

    private static func markerFont(from font: UIFont?) -> UIFont {
        let pointSize = font?.pointSize ?? ZoneTextTypography.baseFontSize(for: .body)
        return .systemFont(ofSize: pointSize, weight: .bold)
    }
}

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
        .system(size: ZoneTextTypography.baseFontSize(for: self), weight: ZoneTextTypography.fontWeight(for: self))
    }

    func localizedName(locale: Locale) -> String {
        switch self {
        case .body:
            return AppLocalization.string("Body", locale: locale)
        case .title:
            return AppLocalization.string("Title", locale: locale)
        case .headline:
            return AppLocalization.string("Headline", locale: locale)
        case .caption:
            return AppLocalization.string("Caption", locale: locale)
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

    func localizedName(locale: Locale) -> String {
        switch self {
        case .system:
            return AppLocalization.string("Sans-Serif", locale: locale)
        case .serif:
            return AppLocalization.string("Serif", locale: locale)
        case .mono:
            return AppLocalization.string("Monospaced", locale: locale)
        case .rounded:
            return AppLocalization.string("Rounded", locale: locale)
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

    var cssFontFamily: String {
        switch self {
        case .system:
            return "-apple-system, BlinkMacSystemFont, \"Segoe UI\", Roboto, Helvetica, Arial, sans-serif"
        case .serif:
            return "ui-serif, Georgia, \"Times New Roman\", serif"
        case .mono:
            return "ui-monospace, \"SF Mono\", Menlo, monospace"
        case .rounded:
            return "ui-rounded, -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif"
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
        case .system:
            return .systemFont(ofSize: size, weight: weight)
        case .serif:
            return Self.systemUIFont(size: size, weight: weight, design: .serif)
        case .rounded:
            return Self.systemUIFont(size: size, weight: weight, design: .rounded)
        case .mono:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    private static func systemUIFont(
        size: CGFloat,
        weight: UIFont.Weight,
        design: UIFontDescriptor.SystemDesign
    ) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = baseFont.fontDescriptor.withDesign(design) else {
            return baseFont
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}

// MARK: - Zone Text Typography

enum ZoneTextTypography {
    static func baseFontSize(for style: TextBlockStyle) -> CGFloat {
        switch style {
        case .caption: return 16
        case .body: return 22
        case .headline: return 26
        case .title: return 32
        }
    }

    static func fontSize(for style: TextBlockStyle, fontScale: CGFloat) -> CGFloat {
        baseFontSize(for: style) * fontScale
    }

    static func lineSpacing(for style: TextBlockStyle, fontScale: CGFloat) -> CGFloat {
        max(floor(fontSize(for: style, fontScale: fontScale) * 0.26), 6)
    }

    static func fontWeight(for style: TextBlockStyle, isBold: Bool = false, emphasized: Bool = false) -> Font.Weight {
        if isBold || emphasized {
            return .bold
        }

        return fontWeight(for: style)
    }

    static func uiFontWeight(for style: TextBlockStyle, isBold: Bool = false, emphasized: Bool = false) -> UIFont.Weight {
        if isBold || emphasized {
            return .bold
        }

        switch style {
        case .title:
            return .bold
        case .headline:
            return .semibold
        case .body, .caption:
            return .regular
        }
    }

    static func font(for zone: ZoneModel, fontScale: CGFloat, emphasized: Bool = false) -> Font {
        font(
            family: zone.fontFamily,
            style: zone.textStyle,
            isBold: zone.isBold,
            isItalic: zone.isItalic,
            fontScale: fontScale,
            emphasized: emphasized
        )
    }

    static func font(
        family: FontFamily,
        style: TextBlockStyle,
        isBold: Bool,
        isItalic: Bool,
        fontScale: CGFloat,
        emphasized: Bool = false
    ) -> Font {
        let base = family.font(
            size: fontSize(for: style, fontScale: fontScale),
            weight: fontWeight(for: style, isBold: isBold, emphasized: emphasized)
        )

        return isItalic ? base.italic() : base
    }

    static func uiFont(for zone: ZoneModel, fontScale: CGFloat, emphasized: Bool = false, monospaced: Bool = false) -> UIFont {
        uiFont(
            family: monospaced ? .mono : zone.fontFamily,
            style: zone.textStyle,
            isBold: zone.isBold,
            isItalic: zone.isItalic,
            fontScale: fontScale,
            emphasized: emphasized
        )
    }

    static func uiFont(
        family: FontFamily,
        style: TextBlockStyle,
        isBold: Bool,
        isItalic: Bool,
        fontScale: CGFloat,
        emphasized: Bool = false
    ) -> UIFont {
        let size = fontSize(for: style, fontScale: fontScale)
        let baseFont = family.uiFont(
            size: size,
            weight: uiFontWeight(for: style, isBold: isBold, emphasized: emphasized)
        )

        guard isItalic,
              let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitItalic) else {
            return baseFont
        }

        return UIFont(descriptor: descriptor, size: size)
    }

    private static func fontWeight(for style: TextBlockStyle) -> Font.Weight {
        switch style {
        case .title:
            return .bold
        case .headline:
            return .semibold
        case .body, .caption:
            return .regular
        }
    }
}

// MARK: - Highlight Color (Marker)
enum HighlightColor: String, Codable, Equatable, CaseIterable {
    case none, yellow, green, red, pink, cyan, accent

    var color: Color? {
        switch self {
        case .none: return nil
        case .yellow: return Color.yellow.opacity(0.4)
        case .green: return Color.green.opacity(0.35)
        case .red: return Color.red.opacity(0.35)
        case .pink: return Color.pink.opacity(0.35)
        case .cyan: return Color.cyan.opacity(0.35)
        case .accent: return ThemeManager.shared.accentColor.color
        }
    }

    var zoneSurfaceTint: Color? {
        switch self {
        case .none:
            return nil
        case .yellow:
            return Color(red: 1.0, green: 0.60, blue: 0.02)
        case .green:
            return Color(red: 0.10, green: 0.82, blue: 0.34)
        case .red:
            return Color(red: 1.0, green: 0.22, blue: 0.18)
        case .pink:
            return Color(red: 1.0, green: 0.18, blue: 0.70)
        case .cyan:
            return Color(red: 0.02, green: 0.80, blue: 1.0)
        case .accent:
            return ThemeManager.shared.accentColor.color
        }
    }

    var zoneSurfaceFill: Color {
        guard let tint = zoneSurfaceTint else {
            return Color(red: 0.075, green: 0.075, blue: 0.082)
        }
        return tint.opacity(0.22)
    }

    var name: String {
        switch self {
        case .none: return "None"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .red: return "Red"
        case .pink: return "Pink"
        case .cyan: return "Cyan"
        case .accent: return "Accent"
        }
    }

    func localizedName(locale: Locale) -> String {
        switch self {
        case .none:
            return AppLocalization.string("None", locale: locale)
        case .yellow:
            return AppLocalization.string("Yellow", locale: locale)
        case .green:
            return AppLocalization.string("Green", locale: locale)
        case .red:
            return AppLocalization.string("Red", locale: locale)
        case .pink:
            return AppLocalization.string("Pink", locale: locale)
        case .cyan:
            return AppLocalization.string("Cyan", locale: locale)
        case .accent:
            return AppLocalization.string("Accent", locale: locale)
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

    func localizedName(locale: Locale) -> String {
        switch self {
        case .primary:
            return AppLocalization.string("Default", locale: locale)
        case .red:
            return AppLocalization.string("Red", locale: locale)
        case .orange:
            return AppLocalization.string("Orange", locale: locale)
        case .yellow:
            return AppLocalization.string("Yellow", locale: locale)
        case .green:
            return AppLocalization.string("Green", locale: locale)
        case .blue:
            return AppLocalization.string("Blue", locale: locale)
        case .purple:
            return AppLocalization.string("Purple", locale: locale)
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
