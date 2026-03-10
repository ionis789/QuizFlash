//
//  CustomMenuButton.swift
//  QuizFlash
//

import SwiftUI

// MARK: - CustomMenuButton

/// A reusable button styled for visual consistency inside context menus and action panels.
///
/// Applies the current app accent colour to the selected state and automatically
/// dims when `disabled` is `true`. A native `.highlight` hover effect is included
/// for iPadOS pointer support.
struct CustomMenuButton: View {

    // MARK: - Configuration

    /// The button's text label.
    let title: String

    /// The SF Symbol name shown to the right of the label.
    let icon: String

    /// When `true`, the label and icon are tinted with the current app accent colour.
    var isSelected: Bool = false

    /// When `true`, the button is non-interactive and rendered at 40% opacity.
    var disabled: Bool = false

    /// Optional override tint used for semantic actions such as destructive delete.
    var tint: Color? = nil

    /// The action to perform when the button is tapped.
    let action: () -> Void

    // MARK: - Private

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var foregroundColor: Color {
        tint ?? (isSelected ? accent : .primary)
    }

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(foregroundColor)
                Spacer(minLength: 0)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(foregroundColor)
                    .frame(width: 24, alignment: .center)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1.0)
        // Native highlight hover effect for iPadOS pointer support.
        .hoverEffect(.highlight)
    }
}

// MARK: - MenuPositionTracker

/// A reference-type tracker that stores the on-screen frame of a floating menu
/// during scroll, without triggering 120 Hz SwiftUI re-renders.
///
/// Use this instead of `@State` or `@Published` for geometry values that update
/// at scroll frequency, where SwiftUI diff overhead would cause layout thrashing.
public final class MenuPositionTracker {

    // MARK: - Properties

    /// The most recently observed frame of the menu in the scroll coordinate space.
    public var rect: CGRect = .zero

    // MARK: - Initializer

    public init() {}
}
