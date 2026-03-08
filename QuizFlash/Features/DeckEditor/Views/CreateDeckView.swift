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

struct CreateDeckView: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationManager.self) private var router

    /// Fetches all available folders to populate the destination picker.
    @Query(sort: \FolderModel.createdAt, order: .reverse) private var folders: [FolderModel]

    // MARK: - State
    @State private var viewModel: CreateDeckViewModel
    @State private var scrollState = CreateDeckScrollState()
    @State private var leadingControlWidth: CGFloat = UIConstants.Size.buttonHeight * 2.1
    @State private var trailingControlWidth: CGFloat = (UIConstants.Size.buttonHeight * 2) + UIConstants.Spacing.small

    /// Tracks the focus state of the deck title text field.
    /// Drives the tab bar visibility rule reactively.
    @FocusState private var isTitleFocused: Bool

    // MARK: - Computed Properties
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var canSave: Bool {
        !viewModel.deckTitle.trimmingCharacters(in: .whitespaces).isEmpty && !viewModel.draftCards.isEmpty
    }
    private var collapsedDeckTitle: String {
        viewModel.deckTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var destinationTitle: String {
        viewModel.selectedFolder?.title ?? "Library"
    }
    private var cardCountText: String {
        let count = viewModel.draftCards.count
        return "\(count) card\(count == 1 ? "" : "s")"
    }
    private var aiToolbarStatusText: String? {
        if viewModel.isMaterializing {
            return "Generating AI..."
        }

        switch viewModel.aiState {
        case .extractingText:
            return "Reading Docs..."
        case .generatingCards:
            return "Generating AI..."
        default:
            return nil
        }
    }
    private var aiVisualStatusText: String? {
        if viewModel.isMaterializing {
            return "Generating"
        }

        switch viewModel.aiState {
        case .extractingText:
            return "Reading Docs"
        case .generatingCards:
            return "Generating"
        default:
            return nil
        }
    }
    private var aiToolbarTint: Color {
        if case .extractingText = viewModel.aiState {
            return .orange
        }
        return .purple
    }
    private var shouldShowFloatingGenerate: Bool {
        scrollState.pillVisible
            && !viewModel.draftCards.isEmpty
            && !isTitleFocused
            && !viewModel.showAIOptionsOverlay
            && !viewModel.showSuccessOverlay
    }
    private var shouldShowCollapsedTitle: Bool {
        scrollState.pillVisible && !viewModel.draftCards.isEmpty
    }

    /// Contextual rule for tab bar visibility.
    ///
    /// Forces the tab bar to hide only while the keyboard is active.
    /// Materialization (card reveal animation) intentionally leaves the bar visible.
    private var tabRule: TabBarVisibilityRule {
        if isTitleFocused {
            return .hidden
        }
        return .implicit
    }

    // MARK: - Initialization
    init(deckToEdit: DeckModel? = nil) {
        _viewModel = State(initialValue: CreateDeckViewModel(deckToEdit: deckToEdit))
    }

    var body: some View {
        GeometryReader { outer in
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        heroHeader

                        cardsListContent
                            .padding(.top, UIConstants.Spacing.large)
                            .padding(.bottom, 132)
                    }
                    .frame(minHeight: outer.size.height, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    isTitleFocused = false
                }

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
            .overlay(alignment: .top) {
                navigationBar(containerWidth: outer.size.width)
            }
            .overlay(alignment: .bottomTrailing) {
                floatingGenerateAction(bottomInset: outer.safeAreaInsets.bottom)
            }
        }
        .environment(scrollState)
        .toolbar(.hidden, for: .navigationBar)
        .swipeBack { dismiss() }
        .confirmationDialog("Generate Cards with AI", isPresented: $viewModel.showAIPickerOptions, titleVisibility: .visible) {
            Button("Choose Photos") { viewModel.showAIPhotoPicker = true }
            Button("Choose PDF") { viewModel.showAIPDFPicker = true }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Extract text from images or documents.") }
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

    // MARK: 1. Header Chrome
    var heroHeader: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            TextField("Untitled Deck", text: $viewModel.deckTitle, axis: .vertical)
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
                .lineLimit(1...2)
                .layoutPriority(1)
                .focused($isTitleFocused)
                .submitLabel(.done)
                .onSubmit { isTitleFocused = false }

            headerMetadataRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UIConstants.Layout.heroScreenEdgeInset)
        .padding(.top, UIConstants.Layout.createDeckPinnedToolbarTopInset + UIConstants.Layout.createDeckHeroTopPadding)
        .padding(.bottom, UIConstants.Spacing.extraLarge)
    }

    private func navigationBar(containerWidth: CGFloat) -> some View {
        let horizontalInset = UIConstants.Layout.compactScreenEdgeInset
        let availableChromeWidth = max(0, containerWidth - (horizontalInset * 2))
        let sideClearance = max(leadingControlWidth, trailingControlWidth)
        let maxTitleWidth = max(
            UIConstants.Size.buttonHeight,
            availableChromeWidth - (sideClearance * 2) - (UIConstants.Spacing.small * 2)
        )

        return ZStack(alignment: .center) {
            CreateDeckCollapsedTitlePill(
                title: collapsedDeckTitle,
                maxWidth: maxTitleWidth,
                isVisible: shouldShowCollapsedTitle
            )
                .allowsHitTesting(false)

            HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
                doneButton
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { newWidth in
                        if abs(leadingControlWidth - newWidth) > 0.5 {
                            leadingControlWidth = newWidth
                        }
                    }

                Spacer(minLength: 0)

                HStack(spacing: UIConstants.Spacing.small) {
                    addCardButton
                    moreActionsButton
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { newWidth in
                    if abs(trailingControlWidth - newWidth) > 0.5 {
                        trailingControlWidth = newWidth
                    }
                }
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, UIConstants.Layout.deckNavigationTopPadding)
    }

    private var headerMetadataRow: some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
            destinationMetadataControl
                .layoutPriority(1)

            Spacer(minLength: 0)

            generateActionControl
        }
        .background {
            Color.clear
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).maxY
                } action: { maxY in
                    let isAbove = maxY < 0
                    if scrollState.pillVisible != isAbove {
                        scrollState.pillVisible = isAbove
                    }
                }
        }
    }

    private var destinationMetadataControl: some View {
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
            HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
                Text(destinationTitle)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(cardCountText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: "chevron.down.compact")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.selectedFolder == nil ? "Choose destination folder, currently Library" : "Choose destination folder, currently \(viewModel.selectedFolder?.title ?? "Library")")
    }

    private var doneButton: some View {
        CreateDeckCapsuleButton(
            action: handleSave,
            isEnabled: canSave,
            accessibilityLabel: "Save deck"
        ) {
                Image(systemName: "checkmark")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
            .foregroundStyle(canSave ? accent : .secondary)
        }
    }

    @ViewBuilder
    private var generateActionControl: some View {
        if let statusText = aiVisualStatusText {
            CreateDeckCapsuleContainer {
                HStack(spacing: UIConstants.Spacing.small) {
                    ProgressView()
                        .tint(aiToolbarTint)
                    Text(statusText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .accessibilityLabel(aiToolbarStatusText ?? statusText)
        } else {
            CreateDeckCapsuleButton(
                action: {
                    isTitleFocused = false
                    viewModel.showAIPickerOptions = true
                },
                accessibilityLabel: "Generate cards with AI"
            ) {
                HStack(spacing: UIConstants.Spacing.small) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text("Generate")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(.purple)
            }
        }
    }

    private var addCardButton: some View {
        CreateDeckChromeButton(
            action: {
                isTitleFocused = false
                viewModel.isCreatingNewCard = true
            },
            accessibilityLabel: "Add card"
        ) {
            CreateDeckChromeButtonLabel(symbol: "plus", tint: accent)
        }
    }

    private func floatingGenerateAction(bottomInset: CGFloat) -> some View {
        generateActionControl
            .padding(.trailing, UIConstants.Layout.compactScreenEdgeInset)
            .padding(.bottom, max(bottomInset, UIConstants.Spacing.standard) + UIConstants.Spacing.extraLarge)
            .opacity(shouldShowFloatingGenerate ? 1 : 0)
            .offset(y: shouldShowFloatingGenerate ? 0 : 18)
            .scaleEffect(shouldShowFloatingGenerate ? 1 : 0.92, anchor: .trailing)
            .allowsHitTesting(shouldShowFloatingGenerate)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: shouldShowFloatingGenerate)
    }

    private var moreMenuContents: some View {
        Group {
            Button("Select Cards") { }
                .disabled(true)
            Button("Delete Deck", role: .destructive) { }
                .disabled(true)
        }
    }

    private var moreActionsButton: some View {
        Menu(content: { moreMenuContents }) {
            CreateDeckChromeButtonLabel(symbol: "ellipsis", tint: accent, fontSize: 22)
                .background {
                    CreateDeckGlassCapsuleBackground()
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More actions")
    }

    // MARK: 2. Cards List Content
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
            .padding(.horizontal, UIConstants.Layout.screenEdgeInset)
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

    private func handleSave() {
        isTitleFocused = false
        viewModel.saveDeck(context: context, router: router, dismiss: dismiss)
    }
}

// MARK: - CreateDeckChromeButton

private struct CreateDeckChromeButton<Label: View>: View {
    let action: () -> Void
    var isEnabled: Bool = true
    let accessibilityLabel: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: 50, height: 50)
                .background {
                CreateDeckGlassCapsuleBackground()
            }
        }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.55)
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct CreateDeckCapsuleButton<Label: View>: View {
    let action: () -> Void
    var isEnabled: Bool = true
    let accessibilityLabel: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            CreateDeckCapsuleContainer(content: label)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct CreateDeckCapsuleContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, UIConstants.Spacing.standard)
            .frame(height: UIConstants.Size.buttonHeight)
            .background {
                CreateDeckGlassCapsuleBackground()
            }
    }
}

private struct CreateDeckChromeButtonLabel: View {
    let symbol: String
    let tint: Color
    var fontSize: CGFloat = 20


    var body: some View {

        Image(systemName: symbol)
            .font(.system(size: fontSize, weight: .bold))
            .fontDesign(.rounded)
            .foregroundStyle(tint)
            .frame(width: 50, height: 50)
    }
}

private struct CreateDeckCollapsedTitlePill: View {
    let title: String
    let maxWidth: CGFloat
    let isVisible: Bool

    @State private var measuredTextWidth: CGFloat = 0

    private var hasTitle: Bool { !title.isEmpty }
    private var horizontalPadding: CGFloat { hasTitle ? UIConstants.Spacing.standard : 0 }
    private var resolvedWidth: CGFloat {
        let intrinsicWidth = measuredTextWidth + (horizontalPadding * 2)
        return min(maxWidth, max(UIConstants.Size.buttonHeight, intrinsicWidth))
    }

    var body: some View {
        ZStack {
            if hasTitle {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { newWidth in
                        if abs(measuredTextWidth - newWidth) > 0.5 {
                            measuredTextWidth = newWidth
                        }
                    }
            }

            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: max(0, resolvedWidth - (horizontalPadding * 2)))
        }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, UIConstants.Spacing.small)
            .frame(width: resolvedWidth)
            .frame(height: UIConstants.Size.buttonHeight)
            .background {
                CreateDeckGlassCapsuleBackground()
            }
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.82, anchor: .top)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVisible)
            .accessibilityLabel(title.isEmpty ? "Untitled Deck" : title)
    }
}

private struct CreateDeckGlassCapsuleBackground: View {
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .blur(radius: 10)
                .mask(Capsule().stroke(lineWidth: 4))
                .blendMode(.overlay)
        }
    }
}

@Observable
private final class CreateDeckScrollState {
    var pillVisible: Bool = false
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
