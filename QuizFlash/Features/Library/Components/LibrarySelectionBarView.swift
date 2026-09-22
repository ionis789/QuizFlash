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
    @Environment(AppPreferences.self) private var appPreferences

    @Bindable var viewModel: LibraryViewModel
    let decks: [DeckModel]
    let onDeleteTap: () -> Void
    var onMoveTap: (() -> Void)? = nil
    var onRemoveFromFolderTap: (() -> Void)? = nil
    var canMoveToAnotherFolder = true

    private var selectedCount: Int { viewModel.selectedDecks.count }
    private var hasSelection: Bool { selectedCount > 0 }
    private var canSelectAll: Bool { !viewModel.areAllVisibleDecksSelected(in: decks) }
    private var locale: Locale { appPreferences.resolvedLocale }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    var body: some View {
        SelectionActionToolbar(
            selectedCount: selectedCount,
            actions: toolbarActions
        )
    }

    private var toolbarActions: [SelectionActionToolbarAction] {
        var actions: [SelectionActionToolbarAction] = [
            .text(
                id: "selectAll",
                title: localized("Select All"),
                accessibilityLabel: localized("Select all decks"),
                isEnabled: canSelectAll,
                action: {
                    withAnimation(.selectionToolbarSpring) {
                        viewModel.selectAllVisibleDecks(from: decks)
                    }
                }
            )
        ]

        if let onRemoveFromFolderTap {
            actions.append(.icon(
                id: "removeFromFolder",
                systemName: "folder.badge.minus",
                accessibilityLabel: localized("Remove selected decks from folder"),
                isEnabled: hasSelection,
                action: onRemoveFromFolderTap
            ))
        }

        actions.append(contentsOf: [
            .icon(
                id: "folder",
                systemName: "folder",
                accessibilityLabel: localized("Move selected decks"),
                isEnabled: hasSelection && canMoveToAnotherFolder,
                action: { onMoveTap?() }
            ),
            .icon(
                id: "export",
                systemName: "square.and.arrow.up",
                accessibilityLabel: localized("Export selected decks"),
                isEnabled: hasSelection && !viewModel.isExporting,
                showsProgress: viewModel.isExporting,
                action: { viewModel.exportSelectedDecks(from: decks) }
            ),
            .icon(
                id: "delete",
                systemName: "trash",
                accessibilityLabel: deleteAccessibilityLabel,
                isEnabled: hasSelection,
                tint: .destructive,
                action: onDeleteTap
            )
        ])

        return actions
    }

    private var deleteAccessibilityLabel: String {
        selectedCount == 1
            ? localizedFormat("Delete %d selected deck", selectedCount)
            : localizedFormat("Delete %d selected decks", selectedCount)
    }
}
