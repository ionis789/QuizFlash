//
//  LibraryExtension.swift
//  QuizFlash
//

import SwiftUI

// MARK: - Color Extensions

extension Color {

    /// Creates a `Color` from a hexadecimal string.
    ///
    /// Accepts 6-digit (`RRGGBB`) and 8-digit (`RRGGBBAA`) hex strings,
    /// with or without a leading `#`.
    ///
    /// - Parameter hex: A hexadecimal colour string, e.g. `"#FF5733"` or `"FF5733FF"`.
    /// - Returns: A `Color` instance, or `nil` if the string cannot be parsed.
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }

        self.init(red: r, green: g, blue: b, opacity: a)
    }

    /// Returns the colour as an uppercase hex string (`#RRGGBB` or `#RRGGBBAA`).
    ///
    /// Returns `nil` if the colour cannot be represented in the sRGB colour space
    /// (e.g. wide-gamut or pattern colours).
    func toHex() -> String? {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return nil
        }

        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)

        if components.count >= 4 {
            a = Float(components[3])
        }

        if a != 1.0 {
            return String(format: "#%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
}

// MARK: - SortOrder

/// The available sort orders for deck and folder lists in the Library.
enum SortOrder: String, CaseIterable {
    case newest      = "Newest"
    case oldest      = "Oldest"
    case lastEdited  = "Edited"
    case alphabetical = "A-Z"

    /// The SF Symbol name associated with this sort order for use in the UI.
    var icon: String {
        switch self {
        case .newest:       return "arrow.down"
        case .oldest:       return "arrow.up"
        case .lastEdited:   return "pencil"
        case .alphabetical: return "textformat.abc"
        }
    }
}

// MARK: - ViewMode

/// The display mode for the Library's content grid — either a linear list or a 2-column gallery.
enum ViewMode: String, CaseIterable {
    case list    = "List"
    case gallery = "Gallery"

    /// The SF Symbol name representing this view mode in toggle controls.
    var systemImage: String { self == .list ? "list.bullet" : "square.grid.2x2" }
}

// MARK: - ScaleButtonStyle

/// A `ButtonStyle` that applies a subtle scale-down effect on press,
/// providing tactile feedback without altering the button's visual appearance.
struct ScaleButtonStyle: ButtonStyle {
    /// Scales the label to 96% on press, restoring smoothly with an ease-out curve.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - View + Keyboard

extension View {
    /// Dismisses the software keyboard by resigning the first responder.
    ///
    /// Call this from a button action or a tap gesture when you need to
    /// programmatically hide the keyboard without a `FocusState` binding.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
