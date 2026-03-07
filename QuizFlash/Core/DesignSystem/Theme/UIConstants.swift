//
//  UIConstants.swift
//  QuizFlash
//
//  A namespace for application-wide layout constants and design tokens.
//  Import this file wherever you need spacing, radius, shadow, size, or animation values
//  to avoid hard-coded magic numbers in the view layer.
//

import Foundation
import CoreGraphics

// MARK: - UI Constants

/// A caseless namespace enum that groups all application-wide layout design tokens.
///
/// Use the nested namespaces to access values:
/// ```swift
/// .padding(UIConstants.Spacing.standard)
/// .cornerRadius(UIConstants.Radius.card)
/// ```
enum UIConstants {

    // MARK: - Spacing

    /// Standardised spacing and padding values, in points.
    enum Spacing {
        /// 4 pt — used for tightest internal component padding.
        static let tiny: CGFloat = 4
        /// 8 pt — used for compact item spacing.
        static let small: CGFloat = 8
        /// 12 pt — used for moderate internal padding.
        static let medium: CGFloat = 12
        /// 16 pt — the default horizontal/vertical content margin.
        static let standard: CGFloat = 16
        /// 20 pt — used for section spacing.
        static let large: CGFloat = 20
        /// 24 pt — used for larger section spacing.
        static let extraLarge: CGFloat = 24
        /// 32 pt — used for major section separation.
        static let huge: CGFloat = 32
    }

    // MARK: - Corner Radius

    /// Standardised corner radius values, in points.
    enum Radius {
        /// 8 pt — tight radius for compact elements (chips, tags).
        static let small: CGFloat = 8
        /// 12 pt — standard radius for list rows and small cards.
        static let medium: CGFloat = 12
        /// 16 pt — the default card corner radius.
        static let card: CGFloat = 16
        /// 22 pt — large radius for panels and bottom sheets.
        static let large: CGFloat = 22
        /// 32 pt — maximum radius for pill-shaped elements.
        static let maximum: CGFloat = 32
    }

    // MARK: - Shadow

    /// Standardised shadow blur radii and offsets, in points.
    enum Shadow {
        /// 4 pt — subtle shadow for hover/lift states.
        static let lightRadius: CGFloat = 4
        /// 12 pt — standard card drop shadow.
        static let mediumRadius: CGFloat = 12
        /// 24 pt — deep shadow for modal sheets.
        static let heavyRadius: CGFloat = 24
        /// Default vertical shadow offset.
        static let yOffset: CGFloat = 4
    }

    // MARK: - Size

    /// Standardised element sizes (icons, buttons, cards), in points.
    enum Size {
        /// 16 pt — small inline icon.
        static let iconSmall: CGFloat = 16
        /// 24 pt — standard icon size.
        static let iconStandard: CGFloat = 24
        /// 32 pt — large icon or avatar.
        static let iconLarge: CGFloat = 32
        /// 50 pt — standard tappable button height.
        static let buttonHeight: CGFloat = 50
        /// 120 pt — minimum card height in grid/list.
        static let cardMinHeight: CGFloat = 120
    }

    // MARK: - Animation

    /// Standardised animation duration values, in seconds.
    ///
    /// Use these constants with `withAnimation` or `Animation` to ensure
    /// consistent motion feel across the application.
    enum Animation {
        /// 0.15 s — instant micro-interactions (icon state change).
        static let instant: Double = 0.15
        /// 0.25 s — standard UI transitions (expand/collapse, fade).
        static let standard: Double = 0.25
        /// 0.35 s — slightly slower transitions for larger elements.
        static let medium: Double = 0.35
        /// 0.5  s — slow, deliberate transitions (sheet, modal).
        static let slow: Double = 0.5
    }
}
