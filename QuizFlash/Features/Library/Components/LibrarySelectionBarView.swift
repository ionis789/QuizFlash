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
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    viewModel.exitSelectionMode()
                }
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .frame(height: UIConstants.Size.selectionToolbarControl)
                    .glassButton(shape: .capsule)
            }
            .buttonStyle(.plain)

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
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
        .padding(.bottom, 12)
        .contentShape(Rectangle())  // Absorb all taps including padding — prevent fall-through to layers below.
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedCount)
    }

    private var deleteAccessibilityLabel: String {
        "Delete \(selectedCount) selected deck\(selectedCount == 1 ? "" : "s")"
    }
}
