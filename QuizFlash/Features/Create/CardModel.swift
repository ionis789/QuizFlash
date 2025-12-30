//
//  CardModel.swift
//  QuizFlash
//
//  Created by Ion Socol on 30.12.2025.
//

import SwiftUI

struct CardModel: Identifiable {
    var id:UUID = UUID()
    var type: CardType
    var title: String
    var textBody: String
    
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
