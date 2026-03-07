//
//  DeckModel.swift
//  QuizFlash
//
//  Created by Ion Socol on 30.12.2025.
//

import SwiftUI
import SwiftData


@Model
class DeckModel {
    var title: String
    var icon: String
    var colorHex: String
    var createdAt: Date
    var editedAt: Date
    var lastOpenedAt: Date?
    var lastAssignedCardNumber: Int = 0
    
    // Relație opțională către Folder
    var folder: FolderModel?
    
    @Relationship(deleteRule: .cascade)
    var cards: [CardModel] = []

    /// Denormalized card count — updated whenever cards are added or removed.
    /// Avoids faulting the `cards` relationship (which permanently retains
    /// ALL CardModel objects in the iOS 17 ModelContext row cache) just
    /// to read `.count`.
    var cardCount: Int = 0

    init(title: String, icon: String, colorHex: String) {
        self.title = title
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = Date()
        self.editedAt = Date()
        self.lastAssignedCardNumber = 0
    }
}
