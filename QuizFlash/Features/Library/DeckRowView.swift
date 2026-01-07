//
//  DeckRowView.swift
//  QuizFlash
//
//  Created by Ion Socol on 07.01.2026.
//

import SwiftUI

struct DeckRowView: View {
    let deck: DeckModel
    
    var body: some View {
        HStack {
            Text(deck.title)
                .font(.headline)
                .foregroundStyle(Color(.secondaryLabel))
            Spacer()
            Text("Cards in deck(\(deck.cards.count))")
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
        }
    }
}
