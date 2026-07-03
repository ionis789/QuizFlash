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
                .rotationEffect(kind.menuIconRotation)
        }
    }
}

private extension CardKind {
    var menuSystemImage: String {
        switch self {
        case .flashcard:
            return "rectangle.on.rectangle.angled"
        case .quiz:
            return "questionmark.square.dashed"
        }
    }

    var menuIconRotation: Angle {
        switch self {
        case .flashcard:
            return .degrees(90)
        case .quiz:
            return .zero
        }
    }
}
