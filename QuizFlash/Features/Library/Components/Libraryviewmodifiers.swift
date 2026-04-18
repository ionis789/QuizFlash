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
    @Bindable var viewModel: LibraryViewModel
    var context: ModelContext
    var decks: [DeckModel]
    var folders: [FolderModel]

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
                allowedContentTypes: [.data],
                allowsMultipleSelection: true
            ) { result in
                viewModel.handleFileImport(result, context: context)
            }
            .confirmationDialog(
                "Delete \(viewModel.selectedDecks.count) deck\(viewModel.selectedDecks.count == 1 ? "" : "s")?",
                isPresented: $viewModel.showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.deleteSelectedDecks(from: decks, context: context)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
            .confirmationDialog(
                "Delete \"\(viewModel.deckToDelete?.title ?? "")\"?",
                isPresented: Binding(
                    get: { viewModel.deckToDelete != nil },
                    set: { if !$0 { viewModel.deckToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.confirmSingleDeletion(context: context)
                    }
                }
                Button("Cancel", role: .cancel) { viewModel.deckToDelete = nil }
            } message: {
                Text("This deck and all its cards will be deleted.")
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
                Button("Library (All Decks)") {
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

                Button("Cancel", role: .cancel) {
                    viewModel.showMoveConfirmation = false
                    viewModel.deckToMove = nil
                }
            } message: {
                Text(moveDialogMessage)
            }
    }

    private var moveDialogTitle: String {
        if let target = viewModel.deckToMove {
            return "Move \"\(target.title)\""
        }
        return "Move \(viewModel.selectedDecks.count) deck\(viewModel.selectedDecks.count == 1 ? "" : "s")"
    }

    private var moveDialogMessage: String {
        if viewModel.deckToMove != nil {
            return "Choose where this deck should go."
        }
        return "Choose where the selected decks should go."
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
    @Bindable var viewModel: LibraryViewModel

    func body(content: Content) -> some View {
        content
            .alert("Import Error", isPresented: $viewModel.showImportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.importErrorMessage)
            }
            .alert("Import Successful", isPresented: $viewModel.showImportSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("\(viewModel.importedDeckName) imported successfully.")
            }
            .alert("Export Error", isPresented: $viewModel.showExportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.exportErrorMessage)
            }
            .alert("Move Error", isPresented: $viewModel.showMoveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.moveErrorMessage)
            }
    }
}
