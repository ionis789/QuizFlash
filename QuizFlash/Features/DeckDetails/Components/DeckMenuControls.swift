//
//  DeckMenuControls.swift
//  QuizFlash
//
//  Contextual dropdown menu for deck-level actions and sort-order selection.
//  Rendered inside a `VisionOSStyleView` capsule positioned by `DeckActionOverlay`.
//

import SwiftUI

// MARK: - DeckMenuControls

/// A vertical list of contextual actions and sort-order options for the active deck.
///
/// Displayed as a dropdown anchored below (or above) the ellipsis button in
/// `DeckActionOverlay`. All actions are delegated via closures or bindings —
/// this view holds no mutable state beyond `@Bindable` wrappers.
struct DeckMenuControls: View {

    // MARK: - Inputs

    /// The deck whose metadata is displayed in the menu header (not currently shown,
    /// kept for future contextual labels).
    @Bindable var deck: DeckModel
    /// `true` when the parent view is already in selection mode; disables "Select Cards".
    let isSelecting: Bool
    /// The currently active sort order; mutated directly when the user picks a new one.
    @Binding var sortOrder: SortOrder
    /// Controls the menu's own expanded/collapsed state (closed after any selection).
    @Binding var isExpanded: Bool

    /// Called when the user taps "Select Cards".
    var onStartSelection: () -> Void
    /// Called when the user taps "Export Deck". Optional — omits the export row when `nil`.
    var onExport: (() -> Void)?

    // MARK: - Computed Properties

    private var accent: Color { ThemeManager.shared.accentColor.color }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {

            // MARK: Main Actions

            CustomMenuButton(
                title: "Select Cards",
                icon: "checkmark.circle",
                disabled: isSelecting
            ) {
                onStartSelection()
                closeMenu()
            }

            if let onExport {
                CustomMenuButton(
                    title: "Export Deck",
                    icon: "square.and.arrow.up"
                ) {
                    onExport()
                    closeMenu()
                }
            }

            Divider()
                .background(Color.primary.opacity(0.1))
                .padding(.vertical, 4)

            // MARK: Sort Order

            Text("SORT BY")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 2)

            ForEach(SortOrder.allCases, id: \.self) { order in
                CustomMenuButton(
                    title: order.rawValue,
                    icon: sortOrder == order ? "checkmark" : order.icon,
                    isSelected: sortOrder == order
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        sortOrder = order
                    }
                    closeMenu()
                }
            }
        }
        .padding(12)
        .foregroundStyle(.primary)
    }

    // MARK: - Private Helpers

    /// Dismisses the menu with a snappy collapse animation.
    private func closeMenu() {
        withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
            isExpanded = false
        }
    }
}
