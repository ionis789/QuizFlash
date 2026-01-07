//
//  CreateView.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//

import SwiftUI
import SwiftData

struct CreateView: View {
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) var dismiss
    
    // MARK: - State
    @State private var deckTitle: String = ""
    @State private var draftCards: [DraftCard] = []
    @State private var isShowingSheet = false
    @State private var isSavedDeck: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Deck Title")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .textCase(.uppercase)
                    
                    TextField("Ex: Biology", text: $deckTitle)
                        .font(.title2.bold())
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                }
                .padding()
                
                // 2. Draft Cards List
                List {
                    Section {
                        if draftCards.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(draftCards) { card in
                                CardRowView(card: card)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            }
                            .onDelete(perform: deleteDraft)
                        }
                    } header: {
                        HStack {
                            Text("Cards in Deck (\(draftCards.count))")
                            Spacer()
                            Button {
                                isShowingSheet = true
                            } label: {
                               Image(systemName: "plus")
                                    .font(.title.bold())
                            }
                        }
                        .padding(8)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Save Deck") {
                        saveDeckToDatabase()
                    }
                    .disabled(deckTitle.isEmpty || draftCards.isEmpty)
                    .alert("Deck saved successfully", isPresented: $isSavedDeck) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text("You can check your deck in the Library menu.")
                    }
                }
            }
            .sheet(isPresented: $isShowingSheet) {
                AddCardSheetView { front, back in
                    let newDraft = DraftCard(front: front, back: back)

                    withAnimation {
                        draftCards.append(newDraft)
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
    
    // MARK: - Subviews
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.portrait.on.rectangle.portrait.slash")
                .font(.system(size: 40))
                .foregroundStyle(.gray.opacity(0.5))
            Text("No cards yet")
                .font(.headline)
                .foregroundStyle(.gray)
            Text("Tap the plus button to add your first card.")
                .font(.caption)
                .foregroundStyle(.gray.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
    
    // MARK: - Logic
    
    private func deleteDraft(at offsets: IndexSet) {
        draftCards.remove(atOffsets: offsets)
    }
    
    private func saveDeckToDatabase() {
        let newDeck = DeckModel(title: deckTitle, icon: "book.closed.fill", colorHex: nil)
        context.insert(newDeck)
        

        for draft in draftCards {
            let cardModel = CardModel(frontText: draft.front, backText: draft.back)
            cardModel.deck = newDeck
            context.insert(cardModel)
        }
        
        deckTitle = ""
        draftCards = []
        isSavedDeck = true
    }
}
