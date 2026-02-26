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
    @Relationship(deleteRule: .cascade)
    var cards: [CardModel] = []
    
    init(title: String, icon: String, colorHex: String) {
        self.title = title
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = Date()
        self.editedAt = Date()
        self.lastAssignedCardNumber = 0
    }
}
