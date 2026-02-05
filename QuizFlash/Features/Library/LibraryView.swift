// Fișier: QuizFlash/Features/Library/LibraryView.swift

import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) var context
    @Query(sort: \DeckModel.creationDate, order: .reverse) private var decks: [DeckModel]

    @EnvironmentObject var router: NavigationManager
    
    @State private var sortOrder: SortOrder = .newest
    @State private var isSelecting = false
    @State private var selectedDecks: Set<PersistentIdentifier> = []
    @State private var showDeleteConfirmation = false
    @State private var deckToDelete: DeckModel?
    @State private var deckToEditColor: DeckModel?
    @State private var themeManager = ThemeManager.shared

    enum SortOrder: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case lastEdited = "Edited"
        case alphabetical = "A-Z"
        
        var icon: String {
            switch self {
            case .newest: return "arrow.down"
            case .oldest: return "arrow.up"
            case .lastEdited: return "pencil"
            case .alphabetical: return "textformat.abc"
            }
        }
    }
    
    private var sortedDecks: [DeckModel] {
        switch sortOrder {
        case .newest:
            return decks.sorted { $0.creationDate > $1.creationDate }
        case .oldest:
            return decks.sorted { $0.creationDate < $1.creationDate }
        case .lastEdited:
            return decks.sorted { $0.lastEditedDate > $1.lastEditedDate }
        case .alphabetical:
            return decks.sorted { $0.title.lowercased() < $1.title.lowercased() }
        }
    }
    
    // Group decks by date section (Telegram style)
    private var groupedDecks: [(String, [DeckModel])] {
        let calendar = Calendar.current
        var groups: [String: [DeckModel]] = [:]
        
        for deck in sortedDecks {
            let date = sortOrder == .lastEdited ? deck.lastEditedDate : deck.creationDate
            let key = dateGroupKey(for: date, calendar: calendar)
            groups[key, default: []].append(deck)
        }
        
        let sortedKeys = groups.keys.sorted { key1, key2 in
            if key1 == "Today" { return true }
            if key2 == "Today" { return false }
            if key1 == "Yesterday" { return true }
            if key2 == "Yesterday" { return false }
            if key1 == "This Week" { return true }
            if key2 == "This Week" { return false }
            if key1 == "This Month" { return true }
            if key2 == "This Month" { return false }
            return key1 > key2
        }
        
        return sortedKeys.map { ($0, groups[$0]!) }
    }
    
    private func dateGroupKey(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            return "This Week"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .month) {
            return "This Month"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: date)
        }
    }

    var body: some View {
        NavigationStack(path: $router.libraryPath) {
            ScrollView {
                VStack(spacing: 0) {
                    if decks.isEmpty {
                        emptyStateView
                    } else {
                        // Selection toolbar (appears above everything)
                        if !decks.isEmpty {
                            selectionToolbar
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .padding(.bottom, 8)
                        }
                        
                        // Sort picker
                        sortPicker
                            .padding(.horizontal, 20)
                            .padding(.bottom, 16)
                        
                        // Grouped decks
                        LazyVStack(spacing: 0, pinnedViews: []) {
                            ForEach(groupedDecks, id: \.0) { group in
                                Section {
                                    VStack(spacing: 10) {
                                        ForEach(group.1) { deck in
                                            deckRow(for: deck)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 16)
                                } header: {
                                    dateSectionHeader(group.0)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 90)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: DeckModel.self) { deck in
                DeckView(deck: deck)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSelecting)
            .confirmationDialog(
                "Delete \(selectedDecks.count) deck\(selectedDecks.count == 1 ? "" : "s")?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteSelectedDecks()
                }
                Button("Cancel", role: .cancel) {}
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
                        withAnimation {
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
    }
    
    // MARK: - Selection Toolbar
    private var selectionToolbar: some View {
        HStack(spacing: 12) {
            // Select/Done button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isSelecting.toggle()
                    if !isSelecting {
                        selectedDecks.removeAll()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isSelecting ? "checkmark" : "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                    Text(isSelecting ? "Done" : "Select")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isSelecting ? themeManager.accentColor.color.opacity(0.15) : Color(uiColor: .secondarySystemGroupedBackground))
                )
                .foregroundStyle(isSelecting ? themeManager.accentColor.color : .primary)
            }
            
            // Delete button (appears when selecting and has items)
            if isSelecting && !selectedDecks.isEmpty {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.semibold))
                        Text("Delete (\(selectedDecks.count))")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.red.opacity(0.12))
                    )
                    .foregroundStyle(.red)
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            Spacer()
        }
    }
    
    // MARK: - Deck Row
    @ViewBuilder
    private func deckRow(for deck: DeckModel) -> some View {
        HStack(spacing: 12) {
            // Selection circle (animated appearance)
            if isSelecting {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        toggleSelection(deck)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                selectedDecks.contains(deck.id) ? themeManager.accentColor.color : Color.secondary.opacity(0.3),
                                lineWidth: 2
                            )
                            .frame(width: 28, height: 28)
                        
                        if selectedDecks.contains(deck.id) {
                            Circle()
                                .fill(themeManager.accentColor.color)
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedDecks.contains(deck.id))
                }
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            
            // Deck content
            if isSelecting {
                DeckRowView(deck: deck)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            toggleSelection(deck)
                        }
                    }
            } else {
                NavigationLink(value: deck) {
                    DeckRowView(deck: deck)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        deckToEditColor = deck
                    } label: {
                        Label("Change Color", systemImage: "paintpalette")
                    }
                    
                    Button(role: .destructive) {
                        deckToDelete = deck
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
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
    
    // MARK: - Sort Picker
    private var sortPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            sortOrder = order
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: order.icon)
                                .font(.caption2.weight(.semibold))
                            Text(order.rawValue)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(sortOrder == order
                                    ? themeManager.accentColor.color.opacity(0.15)
                                    : Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .foregroundStyle(sortOrder == order ? themeManager.accentColor.color : .secondary)
                    }
                }
            }
        }
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
    
    private func deleteSelectedDecks() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
                                deck.colorHex = color.toHex() ?? "#035efc"
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

// MARK: - Color Extensions
extension Color {
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
