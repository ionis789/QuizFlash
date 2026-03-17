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
    /// Active sort order shown in the native overflow menu.
    @Binding var sortOrder: SortOrder

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

    @State private var leadingControlWidth: CGFloat = 120
    @State private var trailingControlWidth: CGFloat = 108

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(0, proxy.size.width - (UIConstants.Layout.compactScreenEdgeInset * 2))
            let sideReserve = max(leadingControlWidth, trailingControlWidth)
            let maxPillWidth = max(
                UIConstants.Size.capsuleHeight,
                availableWidth - (sideReserve * 2) - (UIConstants.Spacing.medium * 2)
            )

            ZStack(alignment: .center) {

                // Centre layer: collapsed pill (manages its own opacity/scale via DeckScrollState).
                if searchQuery == nil {
                    DeckHeroView(deck: deck, stats: stats, maxWidth: maxPillWidth)
                        .allowsHitTesting(false)
                }

                // Edge layer: back button (leading) and action controls (trailing).
                HStack(alignment: .center) {

                    // Leading: Back button
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(height: UIConstants.Size.capsuleHeight)
                        .glassButton(shape: .capsule)
                    }
                    .buttonStyle(.plain)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { newWidth in
                        if abs(leadingControlWidth - newWidth) > 0.5 {
                            leadingControlWidth = newWidth
                        }
                    }

                    Spacer()

                    // Trailing: Add and menu buttons
                    DeckActionOverlay(
                        deck: deck,
                        isSelecting: isSelecting,
                        sortOrder: $sortOrder,
                        onAdd: onAdd,
                        onStartSelection: onStartSelection,
                        onExport: onExport
                    )
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { newWidth in
                        if abs(trailingControlWidth - newWidth) > 0.5 {
                            trailingControlWidth = newWidth
                        }
                    }
                }
            }
        }
        .frame(height: UIConstants.Size.capsuleHeight)
        .topNavigationChrome()
    }
}
