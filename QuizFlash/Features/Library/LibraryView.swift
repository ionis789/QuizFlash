//
//  LibraryView.swift
//  QuizFlash
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Library View
struct LibraryView: View {
    @Environment(\.modelContext) var context
    @Query(sort: \DeckModel.createdAt, order: .reverse) private var decks: [DeckModel]

    @Environment(NavigationManager.self) var router

    @State private var sortOrder: SortOrder = .newest
    @State private var isSelecting = false
    @State private var selectedDecks: Set<PersistentIdentifier> = []
    @State private var showDeleteConfirmation = false
    @State private var deckToDelete: DeckModel?
    @State private var deckToEditColor: DeckModel?
    @State private var viewMode: ViewMode = .list

    // Import State
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    @State private var showImportSuccess = false
    @State private var importedDeckName = ""

    // Export State (for multi-deck export)
    @State private var isExporting = false
    @State private var exportedURLs: [URL] = []
    @State private var showShareSheet = false
    @State private var showExportError = false
    @State private var exportErrorMessage = ""

    private var accent: Color { ThemeManager.shared.accentColor.color }

    /// Sections for list/gallery; computed via LibraryGrouping (logic lives in LibraryGrouping.swift).
    private var groupedDecks: [DeckSection] {
        LibraryGrouping.sections(decks: decks, sortOrder: sortOrder)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 0) {
                    if decks.isEmpty {
                        emptyStateView
                    } else {
                        content
                    }
                }
                    .padding(.top, 8)
                    .safeAreaInset(edge: .bottom) {
                    Color.clear
                        .frame(height: isSelecting ? 140 : 110)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSelecting)
                }
            }
                .background(Color(uiColor: .systemGroupedBackground))
                .contentShape(Rectangle())
                .onTapGesture {
                guard isSelecting else { return }
                exitSelectionMode()
            }


            bottomFloatingButtons

            if isSelecting {
                selectionBottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { topToolbar }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isSelecting)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewMode)
            .confirmationDialog(
            "Delete \(selectedDecks.count) deck\(selectedDecks.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedDecks()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
            .confirmationDialog(
            "Delete \"\(deckToDelete?.title ?? "")\"?",
            isPresented: .init(
                get: { deckToDelete != nil },
                set: { if !$0 { deckToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let deck = deckToDelete {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        context.delete(deck)
                    }
                }
                deckToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                deckToDelete = nil
            }
        } message: {
            Text("This deck and all its cards will be deleted.")
        }
            .sheet(item: $deckToEditColor) { deck in
            DeckColorPickerSheet(deck: deck)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        // File Importer for .qflash files (multiple selection enabled)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        // Import error alert
        .alert("Import Error", isPresented: $showImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage)
        }
        // Import success alert
        .alert("Import Successful", isPresented: $showImportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(importedDeckName) imported successfully.")
        }
        // Export share sheet
        .sheet(isPresented: $showShareSheet) {
            if !exportedURLs.isEmpty {
                ShareSheet(items: exportedURLs)
            }
        }
        // Export error alert
        .alert("Export Error", isPresented: $showExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage)
        }
        // Import loading overlay
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Importing...")
                            .font(.headline)
                    }
                        .padding(32)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        // Export loading overlay
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Exporting \(selectedDecks.count) deck\(selectedDecks.count == 1 ? "" : "s")...")
                            .font(.headline)
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
                // Import Deck
                Button {
                    showFileImporter = true
                } label: {
                    Label("Import Deck", systemImage: "square.and.arrow.down")
                }

                // Select
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isSelecting = true
                    }
                } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }
                    .disabled(isSelecting)

                // Sort
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                sortOrder = order
                            }
                        } label: {
                            if sortOrder == order {
                                Label(order.rawValue, systemImage: "checkmark")
                            } else {
                                Label(order.rawValue, systemImage: order.icon)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }

                // View
                Menu {
                    Button {
                        viewMode = .list
                    } label: {
                        Label("List", systemImage: ViewMode.list.systemImage)
                    }

                    Button {
                        viewMode = .gallery
                    } label: {
                        Label("Gallery", systemImage: ViewMode.gallery.systemImage)
                    }
                } label: {
                    Label("View", systemImage: viewMode.systemImage)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.bold())
                    .foregroundStyle(accent)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewMode {
        case .list:
            groupedDecksList
                .transition(.opacity)
        case .gallery:
            galleryGrid
                .transition(.opacity)
        }
    }

    private var groupedDecksList: some View {
        LazyVStack(spacing: 0, pinnedViews: []) {
            ForEach(groupedDecks) { section in
                Section {
                    VStack(spacing: 10) {
                        ForEach(section.decks) { deck in
                            deckRow(for: deck)
                        }
                    }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                } header: {
                    dateSectionHeader(section.title)
                }
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
                        ForEach(section.decks) { deck in
                            deckGalleryCell(deck)
                        }
                    }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                } header: {
                    dateSectionHeader(section.title)
                }
            }
        }
            .padding(.top, 8)
    }

    // MARK: - Cells

    private func deckGalleryCell(_ deck: DeckModel) -> some View {
        let isSelected = selectedDecks.contains(deck.id)

        return ZStack(alignment: .topLeading) {
            // UNIFIED BUTTON FOR GALLERY
            Button {
                if isSelecting {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        toggleSelection(deck)
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        router.path.append(deck)
                    }
                }
            } label: {
                DeckRowView(deck: deck)
                    .frame(maxWidth: .infinity)
            }
                .buttonStyle(ScaleButtonStyle())

            if isSelecting {
                selectionIndicator(isSelected: isSelected) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        toggleSelection(deck)
                    }
                }
                    .padding(10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
            .background {
            if isSelecting && isSelected {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(accent, lineWidth: 2)
                    .shadow(color: accent.opacity(0.6), radius: 8, x: 0, y: 0)
                    .padding(1)
                    .transition(.opacity)
            }
        }
            .scaleEffect(isSelecting && isSelected ? 0.96 : 1)
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isSelected)
    }

    @ViewBuilder
    private func deckRow(for deck: DeckModel) -> some View {
        let isSelected = selectedDecks.contains(deck.id)

        HStack(spacing: 12) {
            if isSelecting {
                selectionIndicator(isSelected: isSelected) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        toggleSelection(deck)
                    }
                }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Button {
                if isSelecting {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        toggleSelection(deck)
                    }
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        router.path.append(deck)
                    }
                }
            } label: {
                DeckRowView(deck: deck)
                    .background {
                    if isSelecting && isSelected {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(.gray.opacity(0.7), lineWidth: 2)
                            .transition(.opacity)
                    }
                }
            }
                .buttonStyle(ScaleButtonStyle())
                .contextMenu {
                if !isSelecting {
                    Button {
                        deckToEditColor = deck
                    } label: {
                        Label("Change Color", systemImage: "paintpalette")
                    }

                    Button(role: .destructive) {
                        deckToDelete = deck
                    } label: {
                        Text("Delete")
                            .font(.body)
                    }
                }
            }
                .scaleEffect(isSelecting && isSelected ? 0.9 : 1)
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isSelected)
        }
    }

    private func selectionIndicator(
        isSelected: Bool,
        onToggle: @escaping () -> Void
    ) -> some View {
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .strokeBorder(
                    isSelected ? accent : Color.secondary.opacity(0.25),
                    lineWidth: 2
                )

                if isSelected {
                    Circle()
                        .fill(accent)

                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
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
            Button {
                exitSelectionMode()
            } label: {
                Text("Done")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            // Export button
            Button {
                exportSelectedDecks()
            } label: {
                HStack(spacing: 6) {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                    .font(.title3.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
                .disabled(selectedDecks.isEmpty || isExporting)

            Spacer()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {

                Text("Delete(\(selectedDecks.count))")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
                .disabled(selectedDecks.isEmpty)
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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    router.path.append(AppRoute.settings)
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3.bold())
                    .foregroundStyle(accent)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 30)
                    .glassEffect(shape: .capsule)
            }
                .padding(.leading, 22)

            Spacer()
            deckCountSection()
            Spacer()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    router.path.append(AppRoute.createDeck)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.title3.bold())
                    .foregroundStyle(accent)
                    .padding(14)
                    .glassEffect(cornerRadius: 60, style: .spotlight)
            }
                .padding(.trailing, 22)
        }
            .padding(.bottom, 12)
            .allowsHitTesting(!isSelecting)
            .opacity(isSelecting ? 0.0 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSelecting)
    }


    @ViewBuilder
    private func deckCountSection() -> some View {
        switch decks.count {
        case 0:
            Text("No Decks")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        case 1:
            Text("1 Deck")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        default:
            Text("\(decks.count) Decks")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
    // MARK: - Date Section Header
    private func dateSectionHeader(_ title: String) -> some View {
        HStack {
            Spacer()

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer()
        }
            .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("No Decks Yet")
                .font(.title3.weight(.semibold))

            Text("Create your first deck to start learning")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 80)
            .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func toggleSelection(_ deck: DeckModel) {
        if selectedDecks.contains(deck.id) {
            selectedDecks.remove(deck.id)
        } else {
            selectedDecks.insert(deck.id)
        }
    }

    private func exitSelectionMode() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isSelecting = false
            selectedDecks.removeAll()
        }
    }

    private func deleteSelectedDecks() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            for deck in decks where selectedDecks.contains(deck.id) {
                context.delete(deck)
            }
            selectedDecks.removeAll()
            isSelecting = false
        }
    }

    // MARK: - Import
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            // Filter only .qflash files
            let qflashURLs = urls.filter { $0.pathExtension.lowercased() == "qflash" }

            guard !qflashURLs.isEmpty else {
                importErrorMessage = "Please select .qflash files"
                showImportError = true
                return
            }

            isImporting = true

            Task {
                var importedCount = 0
                var lastImportedName = ""
                var errors: [String] = []

                for url in qflashURLs {
                    do {
                        let importedDeck = try await DeckSharingManager.shared.importDeck(from: url, into: context)
                        importedCount += 1
                        lastImportedName = importedDeck.title
                    } catch {
                        errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }

                await MainActor.run {
                    isImporting = false

                    if importedCount > 0 {
                        if importedCount == 1 {
                            importedDeckName = lastImportedName
                        } else {
                            importedDeckName = "\(importedCount) decks"
                        }
                        showImportSuccess = true
                    }

                    if !errors.isEmpty {
                        importErrorMessage = errors.joined(separator: "\n")
                        showImportError = true
                    }
                }
            }

        case .failure(let error):
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }

    // MARK: - Export
    private func exportSelectedDecks() {
        let selectedDecksList = decks.filter { selectedDecks.contains($0.id) }
        guard !selectedDecksList.isEmpty else { return }

        isExporting = true

        Task {
            var exportedFiles: [URL] = []
            var errors: [String] = []

            for deck in selectedDecksList {
                do {
                    let url = try await DeckSharingManager.shared.exportDeck(deck)
                    exportedFiles.append(url)
                } catch {
                    errors.append("\(deck.title): \(error.localizedDescription)")
                }
            }

            await MainActor.run {
                isExporting = false

                if !exportedFiles.isEmpty {
                    exportedURLs = exportedFiles
                    showShareSheet = true
                }

                if !errors.isEmpty {
                    exportErrorMessage = errors.joined(separator: "\n")
                    showExportError = true
                }
            }
        }
    }
}
