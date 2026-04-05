//
//  LibraryDeckListViews.swift
//  QuizFlash
//
//  Deck list rendering for the Library domain:
//  - grouped list wiring
//  - deck rows
//  - row metadata
//  - row separator
//  - long-press action menu
//

import SwiftUI
import SwiftData

// MARK: - Coordinate Space Name

/// Named by LibraryLayout on its ScrollView; read here by row-level visual effects.
let kLibraryScrollSpace = "libraryScroll"

// MARK: - List View

/// The main list view displaying grouped decks.
/// Relies purely on primitives to ensure performance.
struct LibraryListView: View {
    let groupedDecks: [DeckSection]
    let hiddenSectionHeaderIDs: Set<String>
    let isSelecting: Bool
    let selectedDeckIDs: Set<PersistentIdentifier>
    let activeActionMenuDeckID: PersistentIdentifier?
    let onNavigate: (PersistentIdentifier) -> Void
    let onToggleSelection: (PersistentIdentifier) -> Void
    let onToggleActionMenu: (PersistentIdentifier?) -> Void
    let onEditColor: (LibraryDeckActionTarget) -> Void
    let onDelete: (LibraryDeckActionTarget) -> Void

    var body: some View {
        ForEach(groupedDecks) { section in
                Section {
                ForEach(Array(section.decks.enumerated()), id: \.element.id) { index, deck in
                    LibraryDeckListRow(
                        deck: deck,
                        isFirstInSection: index == 0,
                        isSelecting: isSelecting,
                        isSelected: selectedDeckIDs.contains(deck.id),
                        showActionMenu: activeActionMenuDeckID == deck.id,
                        onNavigate: { onNavigate(deck.id) },
                        onToggleSelection: { onToggleSelection(deck.id) },
                        onToggleActionMenu: { show in onToggleActionMenu(show ? deck.id : nil) },
                        onEditColor: { onEditColor(LibraryDeckActionTarget(id: deck.id, title: deck.title)) },
                        onDelete: { onDelete(LibraryDeckActionTarget(id: deck.id, title: deck.title)) }
                    )
                    .equatable()
                    .padding(.horizontal, UIConstants.Layout.compactScreenEdgeInset)
                    .padding(.top, index == 0 ? 0 : 2)
                    .padding(.bottom, 2)
                    .id(deck.id)
                }
            } header: {
                LibrarySectionHeader(
                    id: section.id,
                    title: section.title,
                    isHidden: hiddenSectionHeaderIDs.contains(section.id)
                )
                    .id("header-\(section.id)")
            }
        }
    }
}

/// A flat Library deck list used in search mode when the grouped timeline
/// chrome is intentionally hidden.
struct LibraryFlatListView: View {
    let decks: [LibraryDeckRowSnapshot]
    let isSelecting: Bool
    let selectedDeckIDs: Set<PersistentIdentifier>
    let activeActionMenuDeckID: PersistentIdentifier?
    let onNavigate: (PersistentIdentifier) -> Void
    let onToggleSelection: (PersistentIdentifier) -> Void
    let onToggleActionMenu: (PersistentIdentifier?) -> Void
    let onEditColor: (LibraryDeckActionTarget) -> Void
    let onDelete: (LibraryDeckActionTarget) -> Void

    var body: some View {
        ForEach(Array(decks.enumerated()), id: \.element.id) { index, deck in
            LibraryDeckListRow(
                deck: deck,
                isFirstInSection: index == 0,
                isSelecting: isSelecting,
                isSelected: selectedDeckIDs.contains(deck.id),
                showActionMenu: activeActionMenuDeckID == deck.id,
                onNavigate: { onNavigate(deck.id) },
                onToggleSelection: { onToggleSelection(deck.id) },
                onToggleActionMenu: { show in onToggleActionMenu(show ? deck.id : nil) },
                onEditColor: { onEditColor(LibraryDeckActionTarget(id: deck.id, title: deck.title)) },
                onDelete: { onDelete(LibraryDeckActionTarget(id: deck.id, title: deck.title)) }
            )
            .equatable()
            .padding(.horizontal, UIConstants.Layout.compactScreenEdgeInset)
            .padding(.top, index == 0 ? 0 : 2)
            .padding(.bottom, 2)
            .id(deck.id)
        }
    }
}
