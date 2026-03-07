//
//  CreateDeckView.swift
//  QuizFlash
//
//  Abstract:
//  Primary entry point for creating or editing a deck.
//  Delegates all state and business logic to `CreateDeckViewModel`.
//  Manages only local UI concerns: keyboard focus and tab-bar visibility.
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Preference Key for Scroll Tracking

/// Accumulates the scroll view's origin offset so the nav-bar and hero title
/// can react to the user's scroll position.
struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

struct CreateDeckView: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationManager.self) private var router
    
    /// Fetches all available folders to populate the destination picker.
    @Query(sort: \FolderModel.createdAt, order: .reverse) private var folders: [FolderModel]
    
    // MARK: - State
    @State private var viewModel: CreateDeckViewModel
    
    /// Tracks the focus state of the deck title text field.
    /// Drives the tab bar visibility rule reactively.
    @FocusState private var isTitleFocused: Bool
    
    // MARK: - Computed Properties
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var isGenerating: Bool { viewModel.aiState != .idle }
    
    /// Contextual rule for tab bar visibility.
    ///
    /// Forces the tab bar to hide only while the keyboard is active or AI is generating.
    /// Materialization (card reveal animation) intentionally leaves the bar visible.
    private var tabRule: TabBarVisibilityRule {
        if isTitleFocused || isGenerating {
            return .hidden
        }
        return .implicit
    }
    
    // MARK: - Initialization
    init(deckToEdit: DeckModel? = nil) {
        _viewModel = State(initialValue: CreateDeckViewModel(deckToEdit: deckToEdit))
    }
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            // ── Main Content Area ─────────────────────────────────────────────
            ScrollView {
                VStack(spacing: 0) {
                    // Invisible sensor for scroll offset tracking
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named("scrollSpace")).minY)
                    }
                    .frame(height: 0)
                    
                    heroTitleArea
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                    
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            cardsListContent
                                .padding(.top, 16)
                                .padding(.bottom, 80)
                        } header: {
                            stickyToolBar
                        }
                    }
                }
            }
            .coordinateSpace(name: "scrollSpace")
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                viewModel.scrollOffset = offset
            }
            .safeAreaInset(edge: .top) {
                customNavBar
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                isTitleFocused = false
            }
            
            // ── Overlays ──────────────────────────────────────────────────────
            if viewModel.showSuccessOverlay {
                successOverlay.zIndex(100)
            }
            
            if viewModel.showAIOptionsOverlay {
                AIOptionsOverlay(
                    requestedCardCount: $viewModel.requestedCardCount,
                    extractionMode: $viewModel.extractionMode,
                    pdfAnalysis: viewModel.pdfAnalysis,
                    isForPDF: viewModel.pendingPDFURL != nil,
                    onGenerate: {
                        viewModel.showAIOptionsOverlay = false
                        viewModel.startAIGeneration()
                    },
                    onCancel: {
                        viewModel.showAIOptionsOverlay = false
                        viewModel.selectedAIPhotos = []
                        viewModel.pendingPDFURL = nil
                        viewModel.pdfAnalysis = nil
                    }
                )
                .zIndex(50)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        // ── Gestures ──
        .onChange(of: viewModel.scrollOffset) { _, newOffset in
            if newOffset > 120 {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                dismiss()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .global)
                .onEnded { value in
                    if value.startLocation.x < 40 && value.translation.width > 60 {
                        dismiss()
                    }
                }
        )
        // ── AI Lifecycle ──
        .onChange(of: viewModel.aiState) { _, newState in
            if case .idle = newState, !viewModel.draftCards.isEmpty, !viewModel.isMaterializing {
                viewModel.startMaterializationSequence()
            }
        }
        .fullScreenCover(isPresented: $viewModel.isCreatingNewCard) {
            CreateCardView { frontZone, backZone in
                viewModel.addCard(frontZone: frontZone, backZone: backZone)
            }
        }
        .fullScreenCover(item: $viewModel.cardToEdit) { card in
            CreateCardView(frontZone: card.frontZone, backZone: card.backZone) { f, b in
                viewModel.updateCard(card, frontZone: f, backZone: b)
            }
        }
        .photosPicker(isPresented: $viewModel.showAIPhotoPicker, selection: $viewModel.selectedAIPhotos, matching: .images)
        .fileImporter(isPresented: $viewModel.showAIPDFPicker, allowedContentTypes: [.pdf], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { viewModel.pdfWasSelected(url) }
        }
        // Apply the reactive visibility rule to the global tab bar.
        .customTabBarVisibility(tabRule)
    }
}

// MARK: - Subviews
private extension CreateDeckView {
        
        // MARK: 1. Custom Navigation Bar
        var customNavBar: some View {
            ZStack {
                // Condensed inline title — fades in as the hero area scrolls out of view.
                Text(viewModel.deckTitle.isEmpty ? "Untitled Deck" : viewModel.deckTitle)
                    .font(.headline)
                    .opacity(viewModel.showInlineTitle ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.showInlineTitle)
                
                // Save button aligned to the trailing edge.
                HStack {
                    Spacer()
                    
                    let canSave = !viewModel.deckTitle.trimmingCharacters(in: .whitespaces).isEmpty && !viewModel.draftCards.isEmpty
                    Button {
                        isTitleFocused = false
                        viewModel.saveDeck(context: context, router: router, dismiss: dismiss)
                    } label: {
                        Text("Save")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(canSave ? accent : Color.secondary.opacity(0.15))
                            .foregroundStyle(canSave ? .white : .secondary)
                            .clipShape(Capsule())
                    }
                    .disabled(!canSave)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(viewModel.showInlineTitle ? 1 : 0)
                    .ignoresSafeArea(edges: .top)
            )
            .animation(.easeInOut(duration: 0.2), value: viewModel.showInlineTitle)
        }
        
        // MARK: 2. Hero Title Area
        var heroTitleArea: some View {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Untitled Deck", text: $viewModel.deckTitle)
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                
                // Folder destination picker
                Menu {
                    Button {
                        isTitleFocused = false
                        viewModel.selectedFolder = nil
                    } label: {
                        Label("Library (All Decks)", systemImage: "tray.full")
                    }
                    
                    if !folders.isEmpty {
                        Divider()
                        
                        ForEach(folders) { folder in
                            Button {
                                isTitleFocused = false
                                viewModel.selectedFolder = folder
                            } label: {
                                Label(folder.title, systemImage: "folder")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.selectedFolder == nil ? "tray.full.fill" : "folder.fill")
                        Text(viewModel.selectedFolder?.title ?? "Library")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.selectedFolder == nil ? .secondary : Color.accentColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(viewModel.heroOpacity)
            .scaleEffect(
                viewModel.scrollOffset < 0
                ? max(0.85, 1 + (viewModel.scrollOffset / 400))
                : 1 + (viewModel.scrollOffset / 300),
                anchor: .bottomLeading
            )
        }
        
        // MARK: 3. Sticky Toolbar
        var stickyToolBar: some View {
            HStack(spacing: 14) {
                Group {
                    if case .generatingCards = viewModel.aiState {
                        Label("Generating AI...", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.purple)
                    } else if case .extractingText = viewModel.aiState {
                        Label("Reading Docs...", systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else {
                        Text("\(viewModel.draftCards.count) Card\(viewModel.draftCards.count == 1 ? "" : "s")")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.15), in: .capsule)
                    }
                }
                .transition(.opacity)
                
                Spacer()
                
                Button {
                    isTitleFocused = false
                    viewModel.showAIPickerOptions = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                        Text("Auto AI")
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: .purple.opacity(0.3), radius: 6, y: 3)
                }
                .disabled(isGenerating || viewModel.isMaterializing)
                .opacity(isGenerating || viewModel.isMaterializing ? 0.5 : 1)
                .confirmationDialog("Generate Cards with AI", isPresented: $viewModel.showAIPickerOptions, titleVisibility: .visible) {
                    Button("Choose Photos") { viewModel.showAIPhotoPicker = true }
                    Button("Choose PDF") { viewModel.showAIPDFPicker = true }
                    Button("Cancel", role: .cancel) { }
                } message: { Text("Extract text from images or documents.") }
                
                Button {
                    isTitleFocused = false
                    viewModel.isCreatingNewCard = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .padding(12)
                        .background(accent.opacity(0.15), in: .circle)
                }
            }
            .disabled(isGenerating)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .animation(.easeInOut(duration: 0.3), value: viewModel.aiState)
        }
        
        // MARK: 4. Cards List Content
        var cardsListContent: some View {
            Group {
                if case .extractingText = viewModel.aiState {
                    AIExtractingLoadingView().transition(.asymmetric(insertion: .opacity, removal: .opacity))
                } else if case .generatingCards = viewModel.aiState {
                    AIGenerationSkeletonList(cardCount: viewModel.requestedCardCount).transition(.opacity)
                } else if viewModel.draftCards.isEmpty {
                    emptyStateView.transition(.opacity)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(viewModel.draftCards.enumerated()), id: \.element.id) { index, card in
                            MaterializingCardWrapper(isRevealed: viewModel.revealedCardIndices.contains(index) || !viewModel.isMaterializing) {
                                DetailedCardRowView(card: card, index: index + 1)
                                    .contentShape(Rectangle())
                                    .onTapGesture { isTitleFocused = false; viewModel.cardToEdit = card }
                                    .contextMenu {
                                        Button { viewModel.cardToEdit = card } label: { Label("Edit", systemImage: "pencil") }
                                        Button(role: .destructive) {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { viewModel.deleteCard(card) }
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                                        removal: .scale(scale: 0.8).combined(with: .opacity)
                                    ))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .animation(.easeInOut(duration: 0.35), value: viewModel.aiState)
            .animation(.easeInOut(duration: 0.35), value: viewModel.draftCards.isEmpty)
        }
        
        var emptyStateView: some View {
            VStack(spacing: 14) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No cards yet")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("Tap + to add your first card manually, or use Auto AI to generate them instantly.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture {
                isTitleFocused = false
                viewModel.isCreatingNewCard = true
            }
        }
        
        var successOverlay: some View {
            ZStack {
                Color.clear.background(.ultraThinMaterial).ignoresSafeArea()
                VStack {
                    Spacer(minLength: 60)
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.green)
                            .symbolEffect(.bounce, value: viewModel.showSuccessOverlay)
                        Text("Deck Saved!")
                            .font(.title2.weight(.bold))
                        Text("\(viewModel.draftCards.count) card\(viewModel.draftCards.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 32)
                    .padding(.horizontal, 48)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color(uiColor: .systemBackground))
                            .shadow(color: .black.opacity(0.12), radius: 30, y: 15)
                    )
                    .scaleEffect(viewModel.showSuccessOverlay ? 1 : 0.7, anchor: .top)
                    .opacity(viewModel.showSuccessOverlay ? 1 : 0)
                    .offset(y: viewModel.showSuccessOverlay ? 0 : -80)
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: viewModel.showSuccessOverlay)
                    Spacer()
                }
            }
            .transition(.opacity)
            .allowsHitTesting(false)
        }
}

// MARK: - AIOptionsOverlay

struct AIOptionsOverlay: View {
        @Binding var requestedCardCount: Int
        @Binding var extractionMode: ExtractionMode
        let pdfAnalysis: PDFAnalysisInfo?
        let isForPDF: Bool
        var onGenerate: () -> Void
        var onCancel: () -> Void
        
        var body: some View {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .background(.ultraThinMaterial)
                
                VStack(spacing: 20) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 40))
                        .foregroundStyle(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    
                    Text("AI Generation Settings")
                        .font(.title3.weight(.bold))
                    
                    if isForPDF, let info = pdfAnalysis {
                        pdfQualityBadge(info: info)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    Stepper(value: $requestedCardCount, in: 5...100, step: 5) {
                        Text("**\(requestedCardCount)** cards")
                            .font(.headline)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    modePicker
                    
                    HStack(spacing: 16) {
                        Button("Cancel", action: onCancel)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        
                        Button("Generate", action: onGenerate)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(28)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                        .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
                )
                .padding(.horizontal, 36)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: pdfAnalysis?.quality)
        }
        
        @ViewBuilder
        private func pdfQualityBadge(info: PDFAnalysisInfo) -> some View {
            HStack(spacing: 12) {
                Image(systemName: info.qualityIcon)
                    .foregroundStyle(info.isGoodForFast ? .green : .orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.qualityLabel)
                        .font(.subheadline.weight(.semibold))
                    Text("\(info.pageCount) pages · ~\(info.extractedChars) chars")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(info.recommendation == .fast ? "Fast ✓" : "Quality ✓")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(info.isGoodForFast ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundStyle(info.isGoodForFast ? .green : .orange)
                    .clipShape(Capsule())
            }
            .padding(14)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        
        private var modePicker: some View {
            VStack(spacing: 8) {
                ModeButton(
                    isSelected: extractionMode == .fast,
                    icon: "bolt.fill",
                    iconColor: .yellow,
                    title: "Fast (Free)",
                    description: isForPDF ? "PDFKit + on-device OCR." : "On-device OCR.",
                    onTap: { extractionMode = .fast }
                )
                ModeButton(
                    isSelected: extractionMode == .quality,
                    icon: "eye.fill",
                    iconColor: .purple,
                    title: "Quality (GPT Vision)",
                    description: isForPDF ? "Sends pages to GPT-4o." : "Sends images to GPT-4o.",
                    onTap: { extractionMode = .quality }
                )
            }
        }
}

// MARK: - ModeButton

private struct ModeButton: View {
        let isSelected: Bool
        let icon: String
        let iconColor: Color
        let title: String
        let description: String
        let onTap: () -> Void
        
        var body: some View {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .foregroundStyle(iconColor)
                        .font(.title3)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .font(.title3)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        }
}
