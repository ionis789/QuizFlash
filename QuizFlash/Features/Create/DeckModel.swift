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
    var colorHex: String?
    var creationDate: Date
  
    @Relationship(deleteRule: .cascade)
    var cards: [CardModel] = []
    
    init(title: String, icon: String, colorHex: String?) {
        self.title = title
        self.icon = icon
        self.colorHex = colorHex
        self.creationDate = Date()
    }
}
