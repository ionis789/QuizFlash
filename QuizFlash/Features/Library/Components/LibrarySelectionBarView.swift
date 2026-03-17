//
//  LibrarySelectionBarView.swift
//  QuizFlash
//
//  Bottom contextual bar shown during multi-select.
//  Floats above the tab bar with glass material.
//

import SwiftUI

/// A floating contextual bar displayed at the bottom of the screen during selection mode.
/// Provides actions for selected decks such as exporting or deleting.
struct LibrarySelectionBarView: View {

    @Bindable var viewModel: LibraryViewModel
    let decks: [DeckModel]
    let onDeleteTap: () -> Void
    var onMoveTap: (() -> Void)? = nil

    private var selectedCount: Int { viewModel.selectedDecks.count }
    private var hasSelection: Bool { selectedCount > 0 }

    var body: some View {
        HStack(spacing: UIConstants.Spacing.medium) {

            // ── Done ──────────────────────────────────────────────────────────
            SelectionToolbarCapsuleButton(
                action: {
                    withBottomChromeAnimation {
                        viewModel.exitSelectionMode()
                    }
                },
                accessibilityLabel: "Done selecting decks"
            ) {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer()

            // ── Move ──────────────────────────────────────────────────────────
            SelectionToolbarIconButton(
                isEnabled: hasSelection,
                accessibilityLabel: "Move selected decks",
                action: { onMoveTap?() }
            ) {
                Image(systemName: "folder")
                    .font(.system(size: UIConstants.Size.selectionToolbarIcon, weight: .semibold))
                    .foregroundStyle(hasSelection ? Color.primary : Color.secondary)
            }

            // ── Export ────────────────────────────────────────────────────────
            SelectionToolbarIconButton(
                isEnabled: hasSelection && !viewModel.isExporting,
                accessibilityLabel: "Export selected decks",
                action: { viewModel.exportSelectedDecks(from: decks) }
            ) {
                if viewModel.isExporting {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(hasSelection ? Color.primary : Color.secondary)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: UIConstants.Size.selectionToolbarIcon, weight: .semibold))
                        .foregroundStyle(hasSelection ? Color.primary : Color.secondary)
                }
            }

            // ── Delete ────────────────────────────────────────────────────────
            SelectionToolbarIconButton(
                isEnabled: hasSelection,
                accessibilityLabel: deleteAccessibilityLabel,
                badgeCount: selectedCount,
                action: onDeleteTap
            ) {
                Image(systemName: "trash")
                    .font(.system(size: UIConstants.Size.selectionToolbarIcon, weight: .semibold))
                    .foregroundStyle(hasSelection ? Color.red : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.selectionToolbarSpring, value: selectedCount)
    }

    private var deleteAccessibilityLabel: String {
        "Delete \(selectedCount) selected deck\(selectedCount == 1 ? "" : "s")"
    }
}
