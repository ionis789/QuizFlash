//
//  LibraryStickyBehavior.swift
//  QuizFlash
//
//  Central tuning surface for Library sticky-header behavior.
//

import SwiftUI

/// Single-point tuning surface for the Library sticky timeline.
/// Adjust these values when refining:
/// - the gap between compact `Library` and the pinned date section
/// - the hero -> compact title handoff timing
/// - the visual padding of the date section header
/// - the debug thresholds for sticky tracking
enum LibraryStickyBehavior {
    enum Chrome {
        /// Visual gap between compact `Library` and the pinned date section.
        /// More negative values pull the content closer to the compact title.
        static let compactDateSpacing: CGFloat = -25

        /// Visual gap between the search field chrome and the pinned date section.
        /// Kept separate from the compact Library spacing so search mode can breathe
        /// a bit more without affecting browse-mode sticky timing.
        static let searchDateSpacing: CGFloat = 8

        /// Base top breathing room for the large Library hero title.
        static let heroTopPaddingBase: CGFloat = 20

        /// Extra clearance before the compact title becomes eligible to appear.
        static let collapsedTitleRevealExtraClearance: CGFloat = 28

        /// Small offset applied to the fallback reveal threshold.
        static let collapsedTitleFallbackShowOffset: CGFloat = 6

        /// Hysteresis used when hiding the fallback compact title again.
        static let collapsedTitleFallbackHideHysteresis: CGFloat = 22
    }

    enum SectionHeader {
        /// Default semantic height of the date label itself.
        static let defaultHeight: CGFloat = 24

        /// Vertical padding around the date label inside the section header container.
        /// This influences the native pinned handoff distance.
        static let inlineOuterVerticalPadding: CGFloat = 22

        /// Tight internal padding inside the date label.
        static let labelVerticalPadding: CGFloat = 2

        /// Top spacing for the first deck under a date section.
        static let firstDeckTopPadding: CGFloat = 0

        /// Top spacing for regular decks inside the same section.
        static let regularDeckTopPadding: CGFloat = 16
    }

    enum Debug {
        /// Native sticky host top. Keep at `0` unless the scroll host changes.
        static let pinnedStartThresholdY: CGFloat = 0

        /// Marker for when the compact title has fully passed over the current section.
        static let passedCompactTitleThresholdY: CGFloat = 0

        /// Container top inset used to convert the measured label frame into the
        /// effective section-header container frame.
        static let pinnedStartHeaderTopInset: CGFloat = SectionHeader.inlineOuterVerticalPadding
    }

    enum Handoff {
        /// Start the visual disappearance a little before the compact title has
        /// fully passed the current date section.
        static let compactTitleHideLeadDistance: CGFloat = 5

        /// Delay the visual reappearance slightly when scrolling back upward so the
        /// fade-in is visible instead of happening exactly on the threshold line.
        static let compactTitleRevealLagDistance: CGFloat = 5
    }
}
