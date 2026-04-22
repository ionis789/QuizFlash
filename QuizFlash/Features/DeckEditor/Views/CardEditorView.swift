//
//  CardEditorView.swift
//  QuizFlash
//
//  Routes deck-editor destinations into the appropriate card editor surface.
//

import SwiftUI

struct CardEditorView: View {
    let destination: CardEditorDestination
    var searchQuery: String? = nil
    var onSave: (DraftCardContent) -> Void

    var body: some View {
        switch destination.kind {
        case .flashcard:
            flashcardEditor
        case .match:
            matchEditor
        case .quiz:
            quizEditor
        case .write:
            writeEditor
        }
    }

    private var flashcardEditor: some View {
        let content = resolvedFlashcardContent

        return FlashcardEditorView(
            frontZone: content.frontZone,
            backZone: content.backZone,
            searchQuery: searchQuery
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
            searchQuery: searchQuery
        ) { content in
            onSave(.quiz(content))
        }
    }

    private var matchEditor: some View {
        MatchCardEditorView(initialContent: resolvedMatchContent) { content in
            onSave(.match(content))
        }
    }

    private var resolvedMatchContent: MatchCardContent {
        switch destination {
        case .create:
            return .empty
        case .createFromDraft(_, let draftCard):
            return draftCard.content.matchCompatibilityContent
        case .edit(let draftCard):
            if case .match(let content) = draftCard.content {
                return content
            }
            return .empty
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

    private var writeEditor: some View {
        WriteCardEditorView(initialContent: resolvedWriteContent) { content in
            onSave(.write(content))
        }
    }

    private var resolvedWriteContent: WriteCardContent {
        switch destination {
        case .create:
            return .empty
        case .createFromDraft:
            return .empty
        case .edit(let draftCard):
            if case .write(let content) = draftCard.content {
                return content
            }
            return .empty
        }
    }
}
