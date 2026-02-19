//
//  CreateView.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//
//  Deck creation and editing view with Apple Notes-style card editor.
//

import SwiftUI
import SwiftData

struct CreateView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(NavigationManager.self) private var router

    @State private var viewModel: CreateViewModel
    @FocusState private var isTitleFocused: Bool

    private var accent: Color { ThemeManager.shared.accentColor.color }

    init(deckToEdit: DeckModel? = nil) {
        _viewModel = State(initialValue: CreateViewModel(deckToEdit: deckToEdit))
    }

    var body: some View {
        ZStack {
            // Background
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                isTitleFocused = false
            }

            // Content

            VStack(spacing: 24) {
                deckInfoSection

                ScrollView {
                    cardsListSection
                    Color.clear.frame(height: 80)
                }
                    .scrollDismissesKeyboard(.interactively)

            }

            // Success overlay
            if viewModel.showSuccessOverlay {
                successOverlay
                    .zIndex(100)
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
                    .disabled(viewModel.deckTitle.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.draftCards.isEmpty)
            }

            if viewModel.deckToEdit != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
            .fullScreenCover(isPresented: $viewModel.isCreatingNewCard) {
            AddCardSheetView { frontZone, backZone in
                viewModel.addCard(frontZone: frontZone, backZone: backZone)
            }
        }
            .fullScreenCover(item: $viewModel.cardToEdit) { card in
            AddCardSheetView(
                frontZone: card.frontZone,
                backZone: card.backZone
            ) { frontZone, backZone in
                viewModel.updateCard(card, frontZone: frontZone, backZone: backZone)
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
                    .onSubmit {
                    isTitleFocused = false
                }

                if !viewModel.deckTitle.isEmpty && isTitleFocused {
                    Button {
                        viewModel.deckTitle = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
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
            // Header
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
                    
                } label: {
                    Label("AI", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
                .padding(.horizontal, 24)

            if viewModel.draftCards.isEmpty {
                emptyStateView
            } else {
                LazyVStack(spacing: 16) {
                    // Folosim Array(enumerated()) pentru a pasa indexul la UI (1, 2, 3...)
                    ForEach(Array(viewModel.draftCards.enumerated()), id: \.element.id) { index, card in
                        CardRowView(card: card, index: index + 1)
                            .contentShape(Rectangle())
                            .onTapGesture {
                            isTitleFocused = false
                            viewModel.cardToEdit = card
                        }
                            .contextMenu {
                            Button {
                                viewModel.cardToEdit = card
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                // Adăugăm animația direct de aici pentru ștergere perfectă
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewModel.deleteCard(card)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        // Tranzitie asimetrică: apare și dispare cu un efect fin de zoom
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .move(edge: .bottom)),
                            removal: .scale(scale: 0.8).combined(with: .opacity)
                        ))
                    }
                }
                    .padding(.horizontal, 20)
                // Esențial: Aceasta declanșează glisarea fluidă a cardurilor de dedesubt când unul este șters
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
                    .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.15), value: viewModel.showSuccessOverlay)
                Spacer()
            }
        }
            .transition(.opacity)
            .allowsHitTesting(false)
    }
}
