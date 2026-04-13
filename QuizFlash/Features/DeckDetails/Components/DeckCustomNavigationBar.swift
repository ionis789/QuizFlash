//
//  DeckCustomNavigationBar.swift
//  QuizFlash
//
//  Shared collapsible-title navigation bar adapter for the deck-detail screen.
//

import SwiftUI

// MARK: - DeckCustomNavigationBar

struct DeckCustomNavigationBar: View {

    // MARK: - Inputs

    /// The deck whose title is shown in the collapsed pill.
    let deck: DeckModel
    /// Aggregate stats forwarded to `DeckHeroView` for the mastery ring.
    let stats: DeckStats
    /// The back-button label frozen at push time (never re-read from router state).
    let backLabel: String
    /// When non-`nil`, the search filter banner is active and the pill is hidden.
    let searchQuery: String?
    /// `true` when the parent view is in multi-card selection mode.
    let isSelecting: Bool
    /// Coordinate space used by shared chrome geometry callbacks.
    let coordinateSpaceName: String
    /// Active sort order shown in the native overflow menu.
    @Binding var sortOrder: SortOrder
    /// Active grouping mode shown beside the sort controls.
    @Binding var groupingMode: DeckCardGroupingMode

    // MARK: - Callbacks

    /// Called when the user taps the back button.
    let onBack: () -> Void
    /// Called when the user taps the "+" add button.
    let onAdd: () -> Void
    /// Called when the user taps "Select Cards" in the menu.
    let onStartSelection: () -> Void
    /// Called when the user opens the conversion flow from the deck menu.
    let onConvert: () -> Void
    /// Called when the user taps "Export Deck" in the menu.
    let onExport: () -> Void
    /// Reports the resolved navigation bar height.
    let onHeightChange: (CGFloat) -> Void
    /// Reports the floating chrome bottom edge in the deck coordinate space.
    let onBottomChange: (CGFloat) -> Void

    // MARK: - Computed Properties

    @Environment(DeckScrollState.self) private var scrollState
    @Environment(ThemeManager.self) private var themeManager

    private var accentColor: Color { themeManager.roleColor(.backButtonForeground) }
    private var shouldShowCollapsedTitle: Bool {
        searchQuery == nil && scrollState.pillVisible
    }

    // MARK: - Body

    var body: some View {
        CollapsibleTitleNavigationBar(
            coordinateSpaceName: coordinateSpaceName,
            onHeightChange: onHeightChange,
            onBottomChange: onBottomChange
        ) {
            backButton
        } center: { maxTitleWidth in
            CollapsibleTitlePill(
                title: searchQuery == nil ? deck.title : "",
                maxWidth: maxTitleWidth,
                isVisible: shouldShowCollapsedTitle,
                fallbackTitle: "Untitled Deck"
            )
        } trailing: {
            DeckActionOverlay(
                deck: deck,
                isSelecting: isSelecting,
                sortOrder: $sortOrder,
                groupingMode: $groupingMode,
                onAdd: onAdd,
                onStartSelection: onStartSelection,
                onConvert: onConvert,
                onExport: onExport
            )
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.compact.left")
                    .font(.system(size: UIConstants.Size.navigationChromeIcon, weight: .bold))
                    .fontDesign(.rounded)
                Text(backLabel)
                    .font(.system(size: UIConstants.Size.navigationChromeLabel, weight: .bold))
                    .fontDesign(.rounded)
            }
            .foregroundStyle(accentColor)
        }
        .quizFlashButtonStyle(.surface, shape: .capsule, size: UIConstants.Size.capsuleHeight)
    }
}
