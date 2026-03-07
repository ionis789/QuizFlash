import SwiftUI
import SwiftData

/// A stateless, dumb view for displaying decks.
/// Now uses SwiftData @Query to safely fetch the decks for the folder without mapping the `decks` array on MainActor.
struct FolderDeckListView: View {
    let folder: FolderModel
    
    @Query private var decks: [DeckModel]

    init(folder: FolderModel) {
        self.folder = folder
        
        let folderID = folder.persistentModelID
        let filter = #Predicate<DeckModel> { $0.folder?.persistentModelID == folderID }
        _decks = Query(filter: filter, sort: \DeckModel.createdAt, order: .reverse)
    }

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
