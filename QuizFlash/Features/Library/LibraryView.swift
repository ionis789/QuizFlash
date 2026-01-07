//
//  Library.swift
//  QuizFlash
//
//  Created by Ion Socol on 23.12.2025.
//
import SwiftUI
import SwiftData
struct LibraryView: View {

    @Environment(\.modelContext) var context
    @Query private var decks: [DeckModel]

    var body: some View {
        List {
            if decks.isEmpty {
                emptyStateView
            } else {
                ForEach(decks) { deck in
                    DeckRowView(deck: deck)
                }

                    .onDelete(perform: deleteDeck)
            }
        }
    }

    // MARK: Logic

    private func deleteDeck(at offsets: IndexSet) {
        for index in offsets {
            let deck = decks[index]
            context.delete(deck)
        }
    }


    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.slash")
                .font(.system(size: 40))
                .foregroundStyle(.gray.opacity(0.5))
            Text("No decks yet")
                .font(.headline)
                .foregroundStyle(.gray)
            Text("You can create a first deck in Create menu.")
                .font(.body)
                .foregroundStyle(.gray.opacity(0.8))
                .multilineTextAlignment(.center)
        }
            .frame(maxWidth: .infinity, minHeight: 350)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

}

#Preview {
    LibraryView()
}
