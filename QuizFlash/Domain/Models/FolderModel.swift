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
    var deckCount: Int = 0
    var createdAt: Date

    // Deleting a folder nullifies the relationship on decks (they move to "All Decks")
    @Relationship(deleteRule: .nullify, inverse: \DeckModel.folder)
    var decks: [DeckModel] = []
    
    init(title: String, colorHex: String) {
        self.title = title
        self.colorHex = colorHex
        self.deckCount = 0
        self.createdAt = Date()
    }
}
