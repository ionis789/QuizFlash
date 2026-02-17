//
//  LibraryView.swift
//  QuizFlash
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DeckModel.createdAt, order: .reverse) private var decks: [DeckModel]
    @Environment(NavigationManager.self) private var router

    @State private var viewModel = LibraryViewModel()

    private var accent: Color { ThemeManager.shared.accentColor.color }

    private var groupedDecks: [DeckSection] {
        LibraryGrouping.sections(decks: decks, sortOrder: viewModel.sortOrder)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    if viewModel.isSearching {
                        SearchResultsView(
                            results: viewModel.searchResults,
                            query: viewModel.searchText,
                            onCardTap: { cardID in
                                if let card = context.model(for: cardID) as? CardModel {
                                    viewModel.editingCardFromSearch = card
                                }
                            }
                        )
                        .overlay {
                            if viewModel.isSearchLoading {
                                ZStack {
                                    Color(uiColor: .systemGroupedBackground).opacity(0.8).ignoresSafeArea()
                                    ProgressView().scaleEffect(1.3).tint(accent)
                                }
                                .transition(.opacity)
                            }
                        }
                    } else if decks.isEmpty {
                        emptyStateView
                    } else {
                        content
                    }
                }
                .padding(.top, 8)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: viewModel.isSelecting ? 140 : 110).animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .contentShape(Rectangle())
            .onTapGesture {
                guard viewModel.isSelecting else { return }
                exitSelectionMode()
            }

            if !viewModel.isSearching { bottomFloatingButtons }

            if viewModel.isSelecting && !viewModel.isSearching {
                selectionBottomBar.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { topToolbar }
        .searchable(text: $viewModel.searchText, prompt: "Search")
        .onChange(of: viewModel.searchText) { _, newValue in
            viewModel.updateSearch(query: newValue, decks: decks)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.isSelecting)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.viewMode)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSearching)
        
        .fullScreenCover(item: $viewModel.editingCardFromSearch) { card in
            NavigationStack {
                AddCardSheetView(
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
                        
                        // MARK: FIX - Instantly refresh search results after card edit.
                        // This entirely prevents the user from seeing a "stale highlight" snippet in the search view.
                        viewModel.updateSearch(query: viewModel.searchText, decks: decks)
                    }
                    viewModel.editingCardFromSearch = nil
                }
            }
        }
        
        // Modal Handlers
        .confirmationDialog("Delete \(viewModel.selectedDecks.count) deck\(viewModel.selectedDecks.count == 1 ? "" : "s")?", isPresented: $viewModel.showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteSelectedDecks() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This action cannot be undone.") }
        
        .confirmationDialog("Delete \"\(viewModel.deckToDelete?.title ?? "")\"?", isPresented: .init(get: { viewModel.deckToDelete != nil }, set: { if !$0 { viewModel.deckToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let deck = viewModel.deckToDelete {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { context.delete(deck) }
                }
                viewModel.deckToDelete = nil
            }
            Button("Cancel", role: .cancel) { viewModel.deckToDelete = nil }
        } message: { Text("This deck and all its cards will be deleted.") }
        
        .sheet(item: $viewModel.deckToEditColor) { deck in DeckColorPickerSheet(deck: deck).presentationDetents([.medium]).presentationDragIndicator(.visible) }
        .fileImporter(isPresented: $viewModel.showFileImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in viewModel.handleFileImport(result, context: context) }
        .alert("Import Error", isPresented: $viewModel.showImportError) { Button("OK", role: .cancel) { } } message: { Text(viewModel.importErrorMessage) }
        .alert("Import Successful", isPresented: $viewModel.showImportSuccess) { Button("OK", role: .cancel) { } } message: { Text("\(viewModel.importedDeckName) imported successfully.") }
        .sheet(isPresented: $viewModel.showShareSheet) { if !viewModel.exportedURLs.isEmpty { ShareSheet(items: viewModel.exportedURLs) } }
        .alert("Export Error", isPresented: $viewModel.showExportError) { Button("OK", role: .cancel) { } } message: { Text(viewModel.exportErrorMessage) }
    
        // Import loading overlay
        .overlay {
            if viewModel.isImporting {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.5)
                        Text("Importing...").font(.headline)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        // Export loading overlay
        .overlay {
            if viewModel.isExporting {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.5)
                        Text("Exporting \(viewModel.selectedDecks.count) deck\(viewModel.selectedDecks.count == 1 ? "" : "s")...").font(.headline)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - Top Toolbar
    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { viewModel.showFileImporter = true } label: { Label("Import Deck", systemImage: "square.and.arrow.down") }
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { viewModel.isSelecting = true }
                } label: { Label("Select", systemImage: "checkmark.circle") }
                .disabled(viewModel.isSelecting || viewModel.isSearching)

                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { viewModel.sortOrder = order }
                        } label: {
                            if viewModel.sortOrder == order { Label(order.rawValue, systemImage: "checkmark") }
                            else { Label(order.rawValue, systemImage: order.icon) }
                        }
                    }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }

                Menu {
                    Button { viewModel.viewMode = .list } label: { Label("List", systemImage: ViewMode.list.systemImage) }
                    Button { viewModel.viewMode = .gallery } label: { Label("Gallery", systemImage: ViewMode.gallery.systemImage) }
                } label: { Label("View", systemImage: viewModel.viewMode.systemImage) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3.bold()).foregroundStyle(accent)
            }
        }
    }

    // MARK: - Content
    @ViewBuilder
    private var content: some View {
        switch viewModel.viewMode {
        case .list: groupedDecksList.transition(.opacity)
        case .gallery: galleryGrid.transition(.opacity)
        }
    }

    private var groupedDecksList: some View {
        LazyVStack(spacing: 0, pinnedViews: []) {
            ForEach(groupedDecks) { section in
                Section {
                    VStack(spacing: 10) {
                        ForEach(section.decks) { deck in deckRow(for: deck) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                } header: { dateSectionHeader(section.title) }
            }
        }
    }

    // MARK: - Gallery
    private var galleryGrid: some View {
        let cols = [GridItem(.adaptive(minimum: 160), spacing: 14)]
        return LazyVStack(spacing: 0, pinnedViews: []) {
            ForEach(groupedDecks) { section in
                Section {
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(section.decks) { deck in deckGalleryCell(deck) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                } header: { dateSectionHeader(section.title) }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Cells
    private func deckGalleryCell(_ deck: DeckModel) -> some View {
        let isSelected = viewModel.selectedDecks.contains(deck.id)

        return ZStack(alignment: .topLeading) {
            Button {
                if viewModel.isSelecting {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { toggleSelection(deck) }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { router.path.append(deck) }
                }
            } label: {
                DeckRowView(deck: deck).frame(maxWidth: .infinity)
            }
            .buttonStyle(ScaleButtonStyle())

            if viewModel.isSelecting {
                selectionIndicator(isSelected: isSelected) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { toggleSelection(deck) }
                }
                .padding(10)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .background {
            if viewModel.isSelecting && isSelected {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(accent, lineWidth: 2)
                    .shadow(color: accent.opacity(0.6), radius: 8, x: 0, y: 0)
                    .padding(1)
                    .transition(.opacity)
            }
        }
        .scaleEffect(viewModel.isSelecting && isSelected ? 0.96 : 1)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isSelected)
    }

    @ViewBuilder
    private func deckRow(for deck: DeckModel) -> some View {
        let isSelected = viewModel.selectedDecks.contains(deck.id)

        HStack(spacing: 12) {
            if viewModel.isSelecting {
                selectionIndicator(isSelected: isSelected) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { toggleSelection(deck) }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Button {
                if viewModel.isSelecting {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { toggleSelection(deck) }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { router.path.append(deck) }
                }
            } label: {
                DeckRowView(deck: deck)
                    .background {
                        if viewModel.isSelecting && isSelected {
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(.gray.opacity(0.7), lineWidth: 2)
                                .transition(.opacity)
                        }
                    }
            }
            .buttonStyle(ScaleButtonStyle())
            .contextMenu {
                if !viewModel.isSelecting {
                    Button { viewModel.deckToEditColor = deck } label: { Label("Change Color", systemImage: "paintpalette") }
                    Button(role: .destructive) { viewModel.deckToDelete = deck } label: { Text("Delete").font(.body) }
                }
            }
            .scaleEffect(viewModel.isSelecting && isSelected ? 0.9 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isSelected)
        }
    }

    private func selectionIndicator(isSelected: Bool, onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            ZStack {
                Circle().strokeBorder(isSelected ? accent : Color.secondary.opacity(0.25), lineWidth: 2)
                if isSelected {
                    Circle().fill(accent)
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white).transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 24, height: 24)
            .padding(5)
            .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(ScaleButtonStyle())
        .frame(width: 34, height: 34)
    }

    // MARK: - Bottom bars
    private var selectionBottomBar: some View {
        HStack(spacing: 12) {
            Button { exitSelectionMode() } label: {
                Text("Done").font(.subheadline.bold()).padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            Button {
                viewModel.exportSelectedDecks(from: decks)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if viewModel.isSelecting { viewModel.isSelecting = false }
                }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isExporting { ProgressView().scaleEffect(0.8) }
                    else { Image(systemName: "square.and.arrow.up") }
                }
                .font(.title3.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .disabled(viewModel.selectedDecks.isEmpty || viewModel.isExporting)

            Spacer()

            Button(role: .destructive) {
                viewModel.showDeleteConfirmation = true
            } label: {
                Text("Delete(\(viewModel.selectedDecks.count))").font(.subheadline.bold()).padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial, in: Capsule())
            }
            .disabled(viewModel.selectedDecks.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var bottomFloatingButtons: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { router.path.append(AppRoute.settings) }
            } label: {
                Image(systemName: "gearshape").font(.title3.bold()).foregroundStyle(accent).padding(.vertical, 14).padding(.horizontal, 30).glassEffect(shape: .capsule)
            }
            .padding(.leading, 22)

            Spacer()
            deckCountSection()
            Spacer()
            
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { router.path.append(AppRoute.createDeck) }
            } label: {
                Image(systemName: "plus").font(.title3.bold()).foregroundStyle(accent).padding(14).glassEffect(cornerRadius: 60, style: .spotlight)
            }
            .padding(.trailing, 22)
        }
        .padding(.bottom, 12)
        .allowsHitTesting(!viewModel.isSelecting)
        .opacity(viewModel.isSelecting ? 0.0 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: viewModel.isSelecting)
    }

    @ViewBuilder
    private func deckCountSection() -> some View {
        switch decks.count {
        case 0: Text("No Decks").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        case 1: Text("1 Deck").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        default: Text("\(decks.count) Decks").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Date Section Header
    private func dateSectionHeader(_ title: String) -> some View {
        HStack {
            Spacer()
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule())
            Spacer()
        }
        .padding(.vertical, 12)
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack").font(.system(size: 56)).foregroundStyle(.tertiary)
            Text("No Decks Yet").font(.title3.weight(.semibold))
            Text("Create your first deck to start learning").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
        .padding(.horizontal, 40)
    }

    // MARK: - Actions
    private func toggleSelection(_ deck: DeckModel) {
        if viewModel.selectedDecks.contains(deck.id) { viewModel.selectedDecks.remove(deck.id) }
        else { viewModel.selectedDecks.insert(deck.id) }
    }

    private func exitSelectionMode() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            viewModel.isSelecting = false
            viewModel.selectedDecks.removeAll()
        }
    }

    private func deleteSelectedDecks() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            for deck in decks where viewModel.selectedDecks.contains(deck.id) { context.delete(deck) }
            viewModel.selectedDecks.removeAll()
            viewModel.isSelecting = false
        }
    }
}
