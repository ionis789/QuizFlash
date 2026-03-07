//
//  LibraryViewModifiers.swift
//  QuizFlash
//
//  Abstract:
//  Shared ViewModifier structs for the Library domain.
//
//  These were previously private structs inside LibraryView.swift. They are
//  extracted into a dedicated file because both LibraryView (root tab) and
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

    func body(content: Content) -> some View {
        content
            // NavigationStack must not be the direct root of fullScreenCover.
            // When NavigationStack is the immediate child of the UIHostingController
            // that fullScreenCover creates, UIKit's transition machinery injects
            // _UIReparentingView as a direct subview of UIHostingController.view —
            // an unsupported configuration that corrupts the UIKit view hierarchy.
            // Wrapping in ZStack interposes a standard UIView between
            // UIHostingController.view and NavigationStack's internal
            // UINavigationController, preventing the reparenting attempt.
            .fullScreenCover(item: $viewModel.editingCardFromSearch) { card in
                ZStack {
                    NavigationStack {
                        CreateCardView(
                            frontZone: card.frontZone,
                            backZone: card.backZone,
                            searchQuery: viewModel.searchText
                        ) { frontZone, backZone in
                            if card.frontZone != frontZone || card.backZone != backZone {
                                card.frontZone = frontZone
                                card.backZone = backZone
                                card.editedAt = Date()
                                card.deck?.editedAt = Date()
                                try? context.save()
                                viewModel.updateSearch(query: viewModel.searchText)
                            }
                            viewModel.editingCardFromSearch = nil
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
    }
}
