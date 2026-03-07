//
//  DeckCustomNavigationBar.swift
//  QuizFlash
//
//  Custom navigation bar for the deck-detail screen.
//  Uses a ZStack so the centred pill is absolutely centred regardless of
//  asymmetric leading/trailing item widths.
//

import SwiftUI

// MARK: - DeckCustomNavigationBar

/// A unified, safe-area-respectful custom navigation bar for `DeckView`.
///
/// Layout strategy: a `ZStack` places the leading back button and trailing
/// action overlay as an `HStack` layer, while the collapsed `DeckHeroView` pill
/// floats in the absolute centre — immune to button-width asymmetry.
///
/// This view is fully dumb: it receives all state and callbacks from `DeckView`
/// and `DeckViewModel` via `let` properties, bindings, and closures.
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
    /// Controls the expanded/collapsed state of the context menu.
    @Binding var isMenuExpanded: Bool
    /// The global-coordinate frame of the ellipsis button; used to anchor the dropdown.
    @Binding var menuPosition: CGRect
    /// Provides the live frame of the ellipsis button before the binding is written.
    let menuTracker: MenuPositionTracker

    // MARK: - Callbacks

    /// Called when the user taps the back button.
    let onBack: () -> Void
    /// Called when the user taps the "+" add button.
    let onAdd: () -> Void
    /// Called when the user taps "Select Cards" in the menu.
    let onStartSelection: () -> Void
    /// Called when the user taps "Export Deck" in the menu.
    let onExport: () -> Void

    // MARK: - Computed Properties

    private var accentColor: Color { ThemeManager.shared.accentColor.color }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .center) {

            // Centre layer: collapsed pill (manages its own opacity/scale via DeckScrollState).
            if searchQuery == nil {
                DeckHeroView(deck: deck, stats: stats)
                    .allowsHitTesting(false) // Prevent the pill from intercepting touches.
            }

            // Edge layer: back button (leading) and action controls (trailing).
            HStack(alignment: .center) {

                // Leading: Back button
                Button(action: onBack) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.compact.left")
                            .font(.system(size: 24, weight: .bold)).fontDesign(.rounded)
                        Text(backLabel)
                            .font(.system(size: 13, weight: .bold))
                            .fontDesign(.rounded)
                    }
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(height: 50)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule()
                                    .fill(Color.white.opacity(0.35))
                                    .blur(radius: 10)
                                    .mask(Capsule().stroke(lineWidth: 4))
                                    .blendMode(.overlay)
                            }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Trailing: Add and menu buttons
                DeckActionOverlay(
                    deck: deck,
                    isSelecting: isSelecting,
                    isMenuExpanded: $isMenuExpanded,
                    menuPosition: $menuPosition,
                    menuTracker: menuTracker,
                    onAdd: onAdd,
                    onStartSelection: onStartSelection,
                    onExport: onExport
                )
            }
        }
        // Apply uniform horizontal/top padding for the entire navigation bar.
        .padding(.horizontal, UIConstants.Layout.compactScreenEdgeInset)
        .padding(.top, UIConstants.Layout.deckNavigationTopPadding)
    }
}
