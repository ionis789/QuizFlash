//
//  LibraryViewModifiers.swift
//  QuizFlash
//
//  Abstract:
//  Shared ViewModifier structs for the Library domain.
//
//  These were previously private structs inside LibraryView.swift. They are
//  extracted into a dedicated shared file because both LibraryView (root tab) and
//  FolderView (pushed folder screen) require identical modal and alert behaviour.
//  Extraction avoids duplication while keeping MVVM boundaries intact — both
//  modifiers operate on LibraryViewModel and carry no navigation knowledge.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Modals & Dialogs

/// Encapsulates all sheet, full-screen cover, and confirmation dialog modifiers
/// for the Library domain. Applied identically by LibraryView and FolderView.
struct LibraryModalsAndDialogs: ViewModifier {
    @Environment(AppPreferences.self) private var appPreferences
    @Bindable var viewModel: LibraryViewModel
    var context: ModelContext
    var decks: [DeckModel]
    var folders: [FolderModel]

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $viewModel.editingCardFromSearch) { destination in
                ZStack {
                    CardEditorView(
                        destination: destination,
                        searchQuery: viewModel.searchText
                    ) { content in
                        guard case .edit(let draftCard) = destination,
                              let cardID = draftCard.originalCardID,
                              let card = context.model(for: cardID) as? CardModel else {
                            viewModel.editingCardFromSearch = nil
                            return
                        }

                        if card.cardContent != content {
                            card.cardContent = content
                            card.editedAt = Date()
                            card.deck?.editedAt = Date()
                            viewModel.debounceSearchInput(viewModel.searchText)
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showShareSheet) {
                ShareSheet(items: viewModel.exportedURLs)
            }
            .fileImporter(
                isPresented: $viewModel.showFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: true
            ) { result in
                viewModel.handleFileImport(result, context: context)
            }
            .confirmationDialog(
                viewModel.selectedDecks.count == 1
                    ? localizedFormat("Delete %d deck?", viewModel.selectedDecks.count)
                    : localizedFormat("Delete %d decks?", viewModel.selectedDecks.count),
                isPresented: $viewModel.showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(localized("Delete"), role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.deleteSelectedDecks(from: decks, context: context)
                    }
                }
                Button(localized("Cancel"), role: .cancel) { }
            } message: {
                Text(localized("This action cannot be undone."))
            }
            .confirmationDialog(
                localizedFormat("Delete \"%@\"?", viewModel.deckToDelete?.title ?? ""),
                isPresented: Binding(
                    get: { viewModel.deckToDelete != nil },
                    set: { if !$0 { viewModel.deckToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(localized("Delete"), role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.confirmSingleDeletion(context: context)
                    }
                }
                Button(localized("Cancel"), role: .cancel) { viewModel.deckToDelete = nil }
            } message: {
                Text(localized("This deck and all its cards will be deleted."))
            }
            .confirmationDialog(
                moveDialogTitle,
                isPresented: Binding(
                    get: { viewModel.showMoveConfirmation || viewModel.deckToMove != nil },
                    set: { isPresented in
                        guard !isPresented else { return }
                        viewModel.showMoveConfirmation = false
                        viewModel.deckToMove = nil
                    }
                ),
                titleVisibility: .visible
            ) {
                Button(localized("Library (All Decks)")) {
                    performMove(to: nil)
                }

                if !folders.isEmpty {
                    Divider()

                    ForEach(folders, id: \.persistentModelID) { folder in
                        Button(folder.title) {
                            performMove(to: folder)
                        }
                    }
                }

                Button(localized("Cancel"), role: .cancel) {
                    viewModel.showMoveConfirmation = false
                    viewModel.deckToMove = nil
                }
            } message: {
                Text(moveDialogMessage)
            }
    }

    private var moveDialogTitle: String {
        if let target = viewModel.deckToMove {
            return localizedFormat("Move \"%@\"", target.title)
        }
        return viewModel.selectedDecks.count == 1
            ? localizedFormat("Move %d deck", viewModel.selectedDecks.count)
            : localizedFormat("Move %d decks", viewModel.selectedDecks.count)
    }

    private var moveDialogMessage: String {
        if viewModel.deckToMove != nil {
            return localized("Choose where this deck should go.")
        }
        return localized("Choose where the selected decks should go.")
    }

    private func performMove(to folder: FolderModel?) {
        if viewModel.deckToMove != nil {
            viewModel.moveSingleDeck(from: decks, to: folder, context: context)
        } else {
            viewModel.moveSelectedDecks(from: decks, to: folder, context: context)
        }
    }
}

// MARK: - Alerts

/// Encapsulates all alert modifiers for the Library domain.
/// Applied identically by LibraryView and FolderView.
struct LibraryAlerts: ViewModifier {
    @Environment(AppPreferences.self) private var appPreferences
    @Bindable var viewModel: LibraryViewModel

    private var locale: Locale {
        appPreferences.resolvedLocale
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        AppLocalization.string(value, locale: locale)
    }

    private func localizedFormat(_ value: String.LocalizationValue, _ arguments: CVarArg...) -> String {
        let format = AppLocalization.string(value, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }

    func body(content: Content) -> some View {
        content
            .alert(localized("Import Error"), isPresented: $viewModel.showImportError) {
                Button(localized("OK"), role: .cancel) { }
            } message: {
                Text(viewModel.importErrorMessage)
            }
            .alert(localized("Import Successful"), isPresented: $viewModel.showImportSuccess) {
                Button(localized("OK"), role: .cancel) { }
            } message: {
                Text(localizedFormat("%@ imported successfully.", viewModel.importedDeckName))
            }
            .alert(localized("Export Error"), isPresented: $viewModel.showExportError) {
                Button(localized("OK"), role: .cancel) { }
            } message: {
                Text(viewModel.exportErrorMessage)
            }
            .alert(localized("Move Error"), isPresented: $viewModel.showMoveError) {
                Button(localized("OK"), role: .cancel) { }
            } message: {
                Text(viewModel.moveErrorMessage)
            }
    }
}
