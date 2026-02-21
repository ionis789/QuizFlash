//
//  CreateView.swift
//  QuizFlash
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct CreateView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss)      private var dismiss
    @Environment(NavigationManager.self) private var router

    @State private var viewModel: CreateViewModel
    @FocusState private var isTitleFocused: Bool

    private var accent: Color { ThemeManager.shared.accentColor.color }

    init(deckToEdit: DeckModel? = nil) {
        _viewModel = State(initialValue: CreateViewModel(deckToEdit: deckToEdit))
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isTitleFocused = false }

            VStack(spacing: 24) {
                deckInfoSection

                ScrollView {
                    cardsListSection
                    Color.clear.frame(height: 80)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            if viewModel.showSuccessOverlay {
                successOverlay.zIndex(100)
            }

            if viewModel.showAIOptionsOverlay {
                AIOptionsOverlay(
                    requestedCardCount: $viewModel.requestedCardCount,
                    extractionMode:     $viewModel.extractionMode,
                    pdfAnalysis:        viewModel.pdfAnalysis,
                    isForPDF:           viewModel.pendingPDFURL != nil,
                    onGenerate: {
                        viewModel.showAIOptionsOverlay = false
                        viewModel.startAIGeneration()
                    },
                    onCancel: {
                        viewModel.showAIOptionsOverlay = false
                        viewModel.selectedAIPhotos     = []
                        viewModel.pendingPDFURL        = nil
                        viewModel.pdfAnalysis          = nil
                    }
                )
                .zIndex(50)
            }
        }
        .onAppear {
            if viewModel.deckToEdit == nil && viewModel.deckTitle.isEmpty {
                isTitleFocused = true
            }
        }
        .navigationTitle(viewModel.deckToEdit == nil ? "Create Deck" : "Edit Deck")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    isTitleFocused = false
                    viewModel.saveDeck(context: context, router: router, dismiss: dismiss)
                }
                .fontWeight(.semibold)
                .disabled(
                    viewModel.deckTitle.trimmingCharacters(in: .whitespaces).isEmpty ||
                    viewModel.draftCards.isEmpty
                )
            }

            if viewModel.deckToEdit != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $viewModel.isCreatingNewCard) {
            AddCardSheetView { frontZone, backZone in
                viewModel.addCard(frontZone: frontZone, backZone: backZone)
            }
        }
        .fullScreenCover(item: $viewModel.cardToEdit) { card in
            AddCardSheetView(frontZone: card.frontZone, backZone: card.backZone) { f, b in
                viewModel.updateCard(card, frontZone: f, backZone: b)
            }
        }
        .photosPicker(
            isPresented: $viewModel.showAIPhotoPicker,
            selection:   $viewModel.selectedAIPhotos,
            matching:    .images
        )
        .fileImporter(
            isPresented:          $viewModel.showAIPDFPicker,
            allowedContentTypes:  [.pdf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                // pdfWasSelected face analiza în background și deschide overlay-ul
                // abia după ce are rezultatul — fără spinner suplimentar
                viewModel.pdfWasSelected(url)
            }
        }
        .overlay {
            if viewModel.aiState != .idle {
                AILoadingOverlay(state: viewModel.aiState, onDismiss: viewModel.resetAIState)
            }
        }
    }
}

// MARK: - Subviews
private extension CreateView {

    var deckInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DECK TITLE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                TextField("Enter deck title...", text: $viewModel.deckTitle)
                    .font(.body)
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit { isTitleFocused = false }

                if !viewModel.deckTitle.isEmpty && isTitleFocused {
                    Button { viewModel.deckTitle = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(isTitleFocused ? 0.15 : 0))
                    .padding(-2)
            )
            .scaleEffect(isTitleFocused ? 1.01 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTitleFocused)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    var cardsListSection: some View {
        VStack(spacing: 14) {
            HStack {
                Text("CARDS (\(viewModel.draftCards.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    isTitleFocused = false
                    viewModel.isCreatingNewCard = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Button {
                    isTitleFocused = false
                    viewModel.showAIPickerOptions = true
                } label: {
                    Label("AI", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [.purple.opacity(0.8), .blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .confirmationDialog(
                    "Generate Cards with AI",
                    isPresented: $viewModel.showAIPickerOptions,
                    titleVisibility: .visible
                ) {
                    Button("Choose Photos") { viewModel.showAIPhotoPicker = true }
                    Button("Choose PDF")    { viewModel.showAIPDFPicker = true }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("Extract text from images or documents to instantly create flashcards.")
                }
            }
            .padding(.horizontal, 24)

            if viewModel.draftCards.isEmpty {
                emptyStateView
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(Array(viewModel.draftCards.enumerated()), id: \.element.id) { index, card in
                        CardRowView(card: card, index: index + 1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isTitleFocused = false
                                viewModel.cardToEdit = card
                            }
                            .contextMenu {
                                Button { viewModel.cardToEdit = card } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        viewModel.deleteCard(card)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                                removal:   .scale(scale: 0.8).combined(with: .opacity)
                            ))
                    }
                }
                .padding(.horizontal, 20)
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: viewModel.draftCards.count)
            }
        }
    }

    var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No cards yet")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Tap + to add your first card")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
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
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: viewModel.showSuccessOverlay)
                    Text("Deck Saved!")
                        .font(.title2.weight(.bold))
                    Text("\(viewModel.draftCards.count) card\(viewModel.draftCards.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 44)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                )
                .scaleEffect(viewModel.showSuccessOverlay ? 1 : 0.7, anchor: .top)
                .opacity(viewModel.showSuccessOverlay ? 1 : 0)
                .offset(y: viewModel.showSuccessOverlay ? 0 : -80)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: viewModel.showSuccessOverlay)
                Spacer()
            }
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

// MARK: - AI Options Overlay
struct AIOptionsOverlay: View {
    @Binding var requestedCardCount: Int
    @Binding var extractionMode: ExtractionMode
    let pdfAnalysis: PDFAnalysisInfo?   // nil pentru poze
    let isForPDF: Bool
    var onGenerate: () -> Void
    var onCancel:   () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)

            VStack(spacing: 20) {

                // Header
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 40))
                    .foregroundStyle(LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text("Setări Generare AI")
                    .font(.title3.weight(.bold))

                // PDF Quality Badge — apare doar pentru PDF cu analiza gata
                if isForPDF, let info = pdfAnalysis {
                    pdfQualityBadge(info: info)
                        .transition(.scale.combined(with: .opacity))
                }

                // Card count stepper
                Stepper(value: $requestedCardCount, in: 5...100, step: 5) {
                    Text("**\(requestedCardCount)** carduri")
                        .font(.headline)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Mode selector
                modePicker

                // Action buttons
                HStack(spacing: 16) {
                    Button("Anulează", action: onCancel)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    Button("Generează", action: onGenerate)
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

    // -------------------------------------------------------------------------
    // PDF Quality Badge — afișează scorul PDFKit și recomandarea automată
    // -------------------------------------------------------------------------
    @ViewBuilder
    private func pdfQualityBadge(info: PDFAnalysisInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: info.qualityIcon)
                .foregroundStyle(info.isGoodForFast ? .green : .orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.qualityLabel)
                    .font(.subheadline.weight(.semibold))
                Text("\(info.pageCount) pagini · ~\(info.extractedChars) caractere extrase")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Badge "Recomandat"
            Text(info.recommendation == .fast ? "Rapid ✓" : "Calitate ✓")
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

    // -------------------------------------------------------------------------
    // Mode Picker — Fast vs Quality cu descrieri clare
    // -------------------------------------------------------------------------
    private var modePicker: some View {
        VStack(spacing: 8) {
            // Fast mode
            ModeButton(
                isSelected: extractionMode == .fast,
                icon:        "bolt.fill",
                iconColor:   .yellow,
                title:       "Rapid (Gratuit)",
                description: isForPDF
                    ? "PDFKit + OCR pe device. Gratuit, fără internet."
                    : "OCR pe device. Gratuit, câteva secunde.",
                onTap: { extractionMode = .fast }
            )

            // Quality mode
            ModeButton(
                isSelected: extractionMode == .quality,
                icon:        "eye.fill",
                iconColor:   .purple,
                title:       "Calitate (GPT Vision)",
                description: isForPDF
                    ? "Trimite paginile la GPT-4o. Înțelege diagrame, tabele, math dens."
                    : "Trimite imaginile la GPT-4o. Ideal pentru fotografii cu formule.",
                onTap: { extractionMode = .quality }
            )
        }
    }
}

// MARK: - Mode Button
private struct ModeButton: View {
    let isSelected:  Bool
    let icon:        String
    let iconColor:   Color
    let title:       String
    let description: String
    let onTap:       () -> Void

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
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .font(.title3)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }
}
