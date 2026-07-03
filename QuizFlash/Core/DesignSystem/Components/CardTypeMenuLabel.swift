//
//  CardTypeMenuLabel.swift
//  QuizFlash
//
//  Shared card-type labels for native add-card menus.
//

import SwiftUI

// MARK: - Card Type Menu Label

struct CardTypeMenuLabel: View {
    let kind: CardKind
    let title: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: kind.menuSystemImage)
        }
    }
}

private extension CardKind {
    var menuSystemImage: String {
        switch self {
        case .flashcard:
            return "rectangle.portrait.on.rectangle.portrait.angled"
        case .quiz:
            return "questionmark.square.dashed"
        }
    }
}
