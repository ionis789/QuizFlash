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
import UIKit

// MARK: - UI Constants

/// A caseless namespace enum that groups all application-wide layout design tokens.
///
/// Use the nested namespaces to access values:
/// ```swift
/// .padding(UIConstants.Spacing.standard)
/// .cornerRadius(UIConstants.Radius.card)
/// ```
enum UIConstants {

    /// Returns `true` when the current interface idiom is iPad.
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

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
        /// 20 pt — unified symbol size for top navigation and action buttons.
        static let navigationChromeIcon: CGFloat = 20
        /// 13 pt — unified text size for navigation capsule labels.
        static let navigationChromeLabel: CGFloat = 13
        /// 20 pt — default icon size for circular and capsule action chrome.
        static let actionIcon: CGFloat = navigationChromeIcon
        /// 24 pt — standard icon size.
        static let iconStandard: CGFloat = 24
        /// 32 pt — large icon or avatar.
        static let iconLarge: CGFloat = 32
        /// 28 pt — compact square action control used inside hero titles and dense cards.
        static let actionButtonCompact: CGFloat = 28
        /// 32 pt — standard square action button size.
        static let actionButtonMedium: CGFloat = 32
        /// 50 pt — standard square action button size.
        static let actionButton: CGFloat = 50
        /// 50 pt — standard tappable button height.
        static let buttonHeight: CGFloat = 50
        /// 50 pt — standard height for adaptive glass capsules.
        static let capsuleHeight: CGFloat = 50
        /// 60 pt — unified control size used by selection toolbars.
        static let selectionToolbarControl: CGFloat = 60
        /// 24 pt — icon size used inside 60 pt selection toolbar controls.
        static let selectionToolbarIcon: CGFloat = 24
        /// 120 pt — minimum card height in grid/list.
        static let cardMinHeight: CGFloat = 120
        /// 34 pt — compact width for the inline hero edit control.
        static let heroInlineActionWidth: CGFloat = 34
        /// 30 pt — compact height for the inline hero edit control.
        static let heroInlineActionHeight: CGFloat = 30
        /// 22 pt — compact top-trailing card options button size.
        static let cardOptionsButton: CGFloat = 22
        /// 184 pt — standard height for deck grid cards, sized to preserve breathing room for text and math previews.
        static let deckGridCardHeight: CGFloat = 184
        /// 192 pt — stable height for draft card rows during AI streaming and editor previews.
        static let draftCardRowHeight: CGFloat = 192
        /// 208 pt — compact width for the standardized anchored card context menu.
        static let floatingContextMenuWidth: CGFloat = 208
    }

    // MARK: - Layout

    /// Semantic screen-level layout metrics that adapt between iPhone and iPad.
    ///
    /// Use these values when a layout token represents a screen region or chrome
    /// treatment rather than a low-level spacing primitive.
    enum Layout {
        /// Compact edge inset used by floating controls and navigation chrome.
        static var compactScreenEdgeInset: CGFloat {
            UIConstants.isPad ? UIConstants.Spacing.large : UIConstants.Spacing.standard
        }

        /// Standard edge inset used by full-width screen content containers.
        static var screenEdgeInset: CGFloat {
            UIConstants.isPad ? UIConstants.Spacing.extraLarge : UIConstants.Spacing.large
        }

        /// Wider inset used by hero sections that benefit from extra breathing room.
        static var heroScreenEdgeInset: CGFloat {
            UIConstants.isPad
                ? UIConstants.Spacing.extraLarge + UIConstants.Spacing.tiny
                : UIConstants.Spacing.extraLarge
        }

        /// Default section-to-section spacing for large screen content areas. 
        static var sectionSpacing: CGFloat {
            UIConstants.isPad ? UIConstants.Spacing.huge : UIConstants.Spacing.extraLarge
        }

        /// Top inset used by floating top bars.
        static var floatingTopBarTopPadding: CGFloat {
            UIConstants.isPad ? UIConstants.Spacing.large : UIConstants.Spacing.tiny
        }

        /// Bottom inset used by floating top bars.
        static var floatingTopBarBottomPadding: CGFloat {
            UIConstants.isPad ? UIConstants.Spacing.medium : UIConstants.Spacing.small + 2
        }

        /// Vertical spacing used by the Library empty-search and no-results prompts.
        static var searchPromptSectionSpacing: CGFloat {
            UIConstants.isPad ? UIConstants.Spacing.extraLarge : UIConstants.Spacing.large
        }

        /// Top offset that clears the Library chrome before search guidance content begins.
        static var searchPromptTopPadding: CGFloat {
            UIConstants.Spacing.huge
                + searchPromptSectionSpacing
                + UIConstants.Size.buttonHeight
                + searchPromptSectionSpacing
        }

        /// Maximum width for the Library search-content column.
        static var librarySearchContentMaxWidth: CGFloat {
            UIConstants.isPad ? 860 : 720
        }

        /// Top shadow/vignette height for screens with floating chrome.
        static var topEdgeShadowHeight: CGFloat {
            UIConstants.isPad ? 52 : 40
        }

        /// Expanded top padding for the Home calendar header.
        static var homeCalendarExpandedTopPadding: CGFloat {
            UIConstants.isPad ? UIConstants.Spacing.huge : UIConstants.Spacing.standard
        }

        /// Collapsed top padding for the Home calendar header.
        static var homeCalendarCollapsedTopPadding: CGFloat {
            UIConstants.isPad ? UIConstants.Spacing.standard : 0
        }

        /// Top spacing above the first Home dashboard section.
        static var homeDashboardTopPadding: CGFloat {
            UIConstants.isPad ? UIConstants.Spacing.huge : UIConstants.Spacing.extraLarge
        }

        /// Top spacing for the Deck hero title block.
        static var deckHeroTopPadding: CGFloat {
            UIConstants.isPad ? 176 : 144
        }

        /// Breathing room between the floating Deck chrome and the large hero title block.
        static var deckHeroChromeClearance: CGFloat {
            UIConstants.isPad ? 56 : 44
        }

        /// Extra upward travel required before the Deck hero pill may replace the large title.
        static var deckHeroPillRevealClearance: CGFloat {
            UIConstants.isPad ? 56 : 44
        }

        /// Tighter top spacing for the Create Deck hero block.
        static var createDeckHeroTopPadding: CGFloat {
            UIConstants.isPad ? 52 : UIConstants.Spacing.extraLarge
        }

        /// Top inset that keeps the pinned Create Deck toolbar below the floating save button.
        static var createDeckPinnedToolbarTopInset: CGFloat {
            deckNavigationTopPadding + UIConstants.Size.buttonHeight + UIConstants.Spacing.small
        }

        /// Top inset for the floating Deck navigation bar.
        static var deckNavigationTopPadding: CGFloat {
            UIConstants.isPad ? floatingTopBarTopPadding : UIConstants.Spacing.small
        }
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
