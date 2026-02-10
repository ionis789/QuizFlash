// Fișier: QuizFlash/Features/Library/LibraryView.swift

import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) var context
    @Query(sort: \DeckModel.createdAt, order: .reverse) private var decks: [DeckModel]

    @EnvironmentObject var router: NavigationManager

    @State private var sortOrder: SortOrder = .newest
    @State private var isSelecting = false
    @State private var selectedDecks: Set<PersistentIdentifier> = []
    @State private var showDeleteConfirmation = false
    @State private var deckToDelete: DeckModel?
    @State private var deckToEditColor: DeckModel?
    @State private var viewMode: ViewMode = .list

    private var accent: Color { ThemeManager.shared.accentColor.color }



    // MARK: - Grouping Logic

    // Structure to hold section data
    struct DeckSection: Identifiable {
        let id: String
        let title: String
        let decks: [DeckModel]
        let dateForSorting: Date
    }

    private var groupedDecks: [DeckSection] {
        // Sort all decks first based on user preference
        let sortedAll = decks.sorted { d1, d2 in
            switch sortOrder {
            case .newest: return d1.createdAt > d2.createdAt
            case .oldest: return d1.createdAt < d2.createdAt
            case .lastEdited: return d1.editedAt > d2.editedAt
            case .alphabetical: return d1.title.localizedCaseInsensitiveCompare(d2.title) == .orderedAscending
            }
        }

        // If alphabetical, return one single section
        if sortOrder == .alphabetical {
            if sortedAll.isEmpty { return [] }
            return [DeckSection(id: "all", title: "All Decks", decks: sortedAll, dateForSorting: Date())]
        }

        // Group by date logic
        let calendar = Calendar.current
        let groups = Dictionary(grouping: sortedAll) { deck -> Date in
            let dateToCheck = sortOrder == .lastEdited ? deck.editedAt : deck.createdAt
            return calendar.startOfDay(for: dateToCheck)
        }

        //Transform to Sections
        var sections: [DeckSection] = groups.map { (startOfDay, decksInGroup) in
            let title = getSectionTitle(for: startOfDay, calendar: calendar)
            return DeckSection(
                id: title,
                title: title,
                decks: decksInGroup, // Already sorted from step 1
                dateForSorting: startOfDay
            )
        }

        // Sort Sections based on user preference
        sections.sort { s1, s2 in
            switch sortOrder {
            case .newest, .lastEdited:
                return s1.dateForSorting > s2.dateForSorting // Newest dates first
            case .oldest:
                return s1.dateForSorting < s2.dateForSorting // Oldest dates first
            default:
                return true
            }
        }

        return sections
    }

    // Flexible Date Headers
    private func getSectionTitle(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let now = Date()
        // Check if in current week (but not today/yesterday)
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.dateFormat = "EEEE" // e.g., "Monday"
            return "This Week - " + weekdayFormatter.string(from: date)
        }

        // Check if in current month
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "MMMM d" // e.g., "October 12"
            return dayFormatter.string(from: date)
        }

        // Older
        let fullFormatter = DateFormatter()
        fullFormatter.dateFormat = "MMMM yyyy" // e.g., "September 2025"
        return fullFormatter.string(from: date)
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
    }

    // MARK: - Top Toolbar

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
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
                    .font(.body.weight(.semibold))
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
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()



            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {

                Text("Delete(\(selectedDecks.count))")
                    .fontWeight(.semibold)
                    .font(.subheadline)
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(14)
                    .glassEffect(cornerRadius: 60, style: .spotlight)
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
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
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

    // MARK: - Date Section Header
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
}

// MARK: - Deck Color Picker Sheet
struct DeckColorPickerSheet: View {
    @Bindable var deck: DeckModel
    @Environment(\.dismiss) var dismiss

    private let colors: [Color] = [
            .blue, .purple, .pink, .red, .orange,
            .yellow, .green, .mint, .teal, .cyan
    ]

    private let columns = [
        GridItem(.adaptive(minimum: 60, maximum: 80), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview
                ZStack {
                    Circle()
                        .fill(
                        LinearGradient(
                            colors: [deckColor.opacity(0.7), deckColor.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                        .frame(width: 80, height: 80)

                    Image(systemName: deck.icon.isEmpty ? "sparkles.rectangle.stack.fill" : deck.icon)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }
                    .padding(.top, 20)

                Text(deck.title)
                    .font(.title3.weight(.semibold))

                // Color grid
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(colors, id: \.self) { color in
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                deck.colorHex = color.toHex()!
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(color)
                                    .frame(width: 50, height: 50)
                                    .shadow(color: color.opacity(0.4), radius: 6, y: 3)

                                if deckColor.toHex() == color.toHex() {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
                    .padding(.horizontal, 40)

                Spacer()
            }
                .navigationTitle("Deck Color")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var deckColor: Color {
        Color(hex: deck.colorHex) ?? .blue
    }
}
