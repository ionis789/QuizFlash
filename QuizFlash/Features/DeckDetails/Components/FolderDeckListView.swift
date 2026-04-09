import SwiftUI
import SwiftData

/// A stateless, dumb view for displaying the decks already resolved by the owner view.
struct FolderDeckListView: View {
    let decks: [DeckModel]

    var body: some View {
        LazyVStack(spacing: 16) {
            if decks.isEmpty {
                Text("No decks in this folder.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 24)
            } else {
                ForEach(decks) { deck in
                    DeckRowView(deck: deck)
                        // Bind identity strictly to the database ID
                        .id(deck.persistentModelID)
                }
            }
        }
    }
}
