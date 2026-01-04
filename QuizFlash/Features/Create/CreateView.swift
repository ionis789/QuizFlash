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
    @Environment(\.dismiss) var dismiss // If this is pushed via NavigationLink
    
    // MARK: - State
    @State private var deckTitle: String = ""
    @State private var draftCards: [DraftCard] = []
    @State private var isShowingSheet = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 1. Deck Metadata Header
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
                                    // Hides the default iOS separator lines
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
                        }
                        .padding(.bottom, 8)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden) // Removes default gray background
                
                // 3. Action Button
                Button {
                    isShowingSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Card")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
//            .navigationTitle("Create Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Save Deck") {
                        saveDeckToDatabase()
                    }
                    .disabled(deckTitle.isEmpty || draftCards.isEmpty)
                }
            }
            .sheet(isPresented: $isShowingSheet) {
                AddCardSheetView { front, back in
                    let newDraft = DraftCard(front: front, back: back)
                    // Animation creates a smooth insertion effect
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
            Text("Tap the button below to add your first card.")
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
        // 1. Create the Deck
        let newDeck = DeckModel(title: deckTitle, icon: "book.closed.fill", colorHex: "#007AFF")
        context.insert(newDeck)
        
        // 2. Convert Drafts to Real Models
        for draft in draftCards {
            let cardModel = CardModel(frontText: draft.front, backText: draft.back)
            cardModel.deck = newDeck // Link relationship
            context.insert(cardModel) // Insert into DB
        }
        
        // 3. Reset or Dismiss
        // dismiss() // specific to your navigation flow
        // Or reset state:
        deckTitle = ""
        draftCards = []
    }
}
