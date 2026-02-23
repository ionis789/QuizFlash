//
//  LibraryView.swift
//  QuizFlash
//
//  Coordinator: owns @Query, bindings, presents modals.
//  No layout or styling lives here.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {

    // MARK: - Data
    @Environment(\.modelContext) private var context
    @Query(sort: \DeckModel.createdAt, order: .reverse) private var decks: [DeckModel]
    @Environment(NavigationManager.self) private var router

    // MARK: - State
    @State private var viewModel = LibraryViewModel()

    // MARK: - External Bindings (from MainAppView / tab bar)
    @Binding var externalSearchText: String
    @Binding var isSearchExpanded: Bool
    @Binding var isTabBarHidden: Bool

    // MARK: - Body
    var body: some View {
        LibraryLayout(
            decks: decks,
            viewModel: viewModel,
            router: router,
            onCardTap: { cardID in
                if let card = context.model(for: cardID) as? CardModel {
                    viewModel.editingCardFromSearch = card
                }
            },
            onDeckNavigate: { deck in
                router.path.append(deck)
            },
            onDeleteSelected: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    viewModel.deleteSelectedDecks(from: decks, context: context)
                }
            }
        )
        // ── Sync external search ──────────────────────────────────────────────
        .onChange(of: externalSearchText) { _, newValue in
            viewModel.searchText = newValue
            viewModel.updateSearch(query: newValue, decks: decks)
        }
        .onChange(of: isSearchExpanded) { _, expanded in
            viewModel.isSearching = expanded
            if !expanded {
                viewModel.searchText = ""
                viewModel.searchResults = []
            }
        }
        .onChange(of: viewModel.isSelecting) { _, selecting in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isTabBarHidden = selecting
            }
        }
        // ── Modals ────────────────────────────────────────────────────────────
        .fullScreenCover(item: $viewModel.editingCardFromSearch) { card in
            NavigationStack {
                CreateCardView(
                    frontZone: card.frontZone,
                    backZone: card.backZone,
                    searchQuery: viewModel.searchText
                ) { frontZone, backZone in
                    if card.frontZone != frontZone || card.backZone != backZone {
                        card.frontZone = frontZone
                        card.backZone  = backZone
                        card.editedAt  = Date()
                        card.deck?.editedAt = Date()
                        try? context.save()
                        viewModel.updateSearch(query: viewModel.searchText, decks: decks)
                    }
                    viewModel.editingCardFromSearch = nil
                }
            }
        }
        .sheet(item: $viewModel.deckToEditColor) { deck in
            DeckColorPickerSheet(deck: deck)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
        // ── Confirmation Dialogs ──────────────────────────────────────────────
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
            Button("Cancel", role: .cancel) {}
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
        // ── Alerts ────────────────────────────────────────────────────────────
        .alert("Import Error", isPresented: $viewModel.showImportError) {
            Button("OK", role: .cancel) {}
        } message: { Text(viewModel.importErrorMessage) }
        .alert("Import Successful", isPresented: $viewModel.showImportSuccess) {
            Button("OK", role: .cancel) {}
        } message: { Text("\(viewModel.importedDeckName) imported successfully.") }
        .alert("Export Error", isPresented: $viewModel.showExportError) {
            Button("OK", role: .cancel) {}
        } message: { Text(viewModel.exportErrorMessage) }
    }
}
