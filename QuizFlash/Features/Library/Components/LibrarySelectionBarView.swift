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
    private var actionClusterBackground: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.035))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 0.75)
            }
    }

    var body: some View {
        HStack(spacing: 14) {

            SelectionToolbarCapsuleButton(
                action: {
                    withBottomChromeAnimation {
                        viewModel.exitSelectionMode()
                    }
                },
                accessibilityLabel: "Done selecting decks"
            ) {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Spacer()

            HStack(spacing: 8) {
                SelectionToolbarIconButton(
                    isEnabled: hasSelection,
                    accessibilityLabel: "Move selected decks",
                    action: { onMoveTap?() }
                ) {
                    Image(systemName: "folder")
                        .font(.system(size: UIConstants.Size.selectionToolbarIcon, weight: .semibold))
                        .foregroundStyle(hasSelection ? Color.primary : Color.secondary)
                }

                SelectionToolbarIconButton(
                    isEnabled: hasSelection && !viewModel.isExporting,
                    accessibilityLabel: "Export selected decks",
                    action: { viewModel.exportSelectedDecks(from: decks) }
                ) {
                    if viewModel.isExporting {
                        ProgressView()
                            .scaleEffect(0.78)
                            .tint(hasSelection ? Color.primary : Color.secondary)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: UIConstants.Size.selectionToolbarIcon, weight: .semibold))
                            .foregroundStyle(hasSelection ? Color.primary : Color.secondary)
                    }
                }

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
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background { actionClusterBackground }
        }
        .frame(maxWidth: .infinity)
        .animation(.selectionToolbarSpring, value: selectedCount)
    }

    private var deleteAccessibilityLabel: String {
        "Delete \(selectedCount) selected deck\(selectedCount == 1 ? "" : "s")"
    }
}
