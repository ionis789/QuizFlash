//
//  FolderModel.swift
//  QuizFlash
//
//  Created by Ion Socol.
//

import SwiftUI
import SwiftData

@Model
class FolderModel {
    var id: UUID = UUID()
    var title: String
    var colorHex: String
    var createdAt: Date

    /// Denormalized deck count.
    /// Kept in sync manually at every mutation site (create, delete, move deck).
    /// Reading this plain Int in SwiftUI body is safe — it never faults a
    /// relationship array into the main ModelContext row cache (iOS 17 fix).
    var deckCount: Int = 0

    // Deleting a folder nullifies the relationship on decks (they move to "All Decks")
    @Relationship(deleteRule: .nullify, inverse: \DeckModel.folder)
    var decks: [DeckModel] = []
    
    init(title: String, colorHex: String) {
        self.title = title
        self.colorHex = colorHex
        self.createdAt = Date()
    }
}
