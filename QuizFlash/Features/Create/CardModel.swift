//
//  CardModel.swift
//  QuizFlash
//
//  Created by Ion Socol on 30.12.2025.
//

import SwiftUI
import SwiftData

@Model
class CardModel {
    
    var frontText: String
    var backText: String
    var createdAt: Date
    
    var deck: DeckModel?
    
    init(frontText: String, backText: String) {
        self.frontText = frontText
        self.backText = backText
        self.createdAt = Date()
    }
    
    
}

enum CardType: String, CaseIterable {
    case textOnly, textAndImage
    
    var icon: String {
        switch self {
        case .textOnly: "character.cursor.ibeam"
        case .textAndImage: "richtext.page"
        }
    }
}

// Temporary model for UI rendering before saving to Database
struct DraftCard: Identifiable {
    let id = UUID()
    var front: String
    var back: String
}
