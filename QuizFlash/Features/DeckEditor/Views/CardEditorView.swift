//
//  CardEditorView.swift
//  QuizFlash
//
//  Routes deck-editor destinations into the appropriate card editor surface.
//

import SwiftUI

struct CardEditorView: View {
    @Environment(AppPreferences.self) private var appPreferences

    let destination: CardEditorDestination
    var searchQuery: String? = nil
    var textSizeOverride: FlashcardTextSize? = nil
    var onSave: (DraftCardContent) -> Void

    private var resolvedTextSize: FlashcardTextSize {
        CardEditorTextSizeResolver.resolve(
            override: textSizeOverride,
            defaultTextSize: appPreferences.defaultTextSize
        )
    }

    var body: some View {
        switch destination.kind {
        case .flashcard:
            flashcardEditor
        case .quiz:
            quizEditor
        }
    }

    private var flashcardEditor: some View {
        let content = resolvedFlashcardContent

        return FlashcardEditorView(
            frontZone: content.frontZone,
            backZone: content.backZone,
            searchQuery: searchQuery,
            textSize: resolvedTextSize
        ) { frontZone, backZone in
            onSave(
                .flashcard(
                    FlashcardCardContent(
                        frontZone: frontZone,
                        backZone: backZone,
                        frontType: content.frontType,
                        backType: content.backType
                    )
                )
            )
        }
    }

    private var resolvedFlashcardContent: FlashcardCardContent {
        switch destination {
        case .create:
            return .empty
        case .createFromDraft(_, let draftCard):
            return draftCard.content.flashcardCompatibilityContent
        case .edit(let draftCard):
            return draftCard.content.flashcardCompatibilityContent
        }
    }

    private var quizEditor: some View {
        QuizCardEditorView(
            initialContent: resolvedQuizContent,
            searchQuery: searchQuery,
            textSize: resolvedTextSize
        ) { content in
            onSave(.quiz(content))
        }
    }

    private var resolvedQuizContent: QuizCardContent {
        switch destination {
        case .create:
            return .empty
        case .createFromDraft:
            return .empty
        case .edit(let draftCard):
            if case .quiz(let content) = draftCard.content {
                return content
            }
            return .empty
        }
    }

}

enum CardEditorTextSizeResolver {
    static func resolve(
        override: FlashcardTextSize?,
        defaultTextSize: FlashcardTextSize
    ) -> FlashcardTextSize {
        override ?? defaultTextSize
    }
}
