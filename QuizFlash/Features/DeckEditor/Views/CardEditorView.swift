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
    @State private var flashcardDraftContent: FlashcardCardContent

    init(
        destination: CardEditorDestination,
        searchQuery: String? = nil,
        textSizeOverride: FlashcardTextSize? = nil,
        onSave: @escaping (DraftCardContent) -> Void
    ) {
        self.destination = destination
        self.searchQuery = searchQuery
        self.textSizeOverride = textSizeOverride
        self.onSave = onSave
        _flashcardDraftContent = State(initialValue: Self.resolvedFlashcardContent(for: destination))
    }

    private var resolvedTextSize: FlashcardTextSize {
        CardEditorTextSizeResolver.resolve(
            override: textSizeOverride,
            defaultTextSize: appPreferences.defaultTextSize
        )
    }

    var body: some View {
        let _ = recordCardEditorLifecycle("card-editor-body")
        switch destination.kind {
        case .flashcard:
            flashcardEditor
        case .quiz:
            quizEditor
        }
    }

    private var flashcardEditor: some View {
        let content = flashcardDraftContent

        return FlashcardEditorView(
            frontZone: content.frontZone,
            backZone: content.backZone,
            searchQuery: searchQuery,
            textSize: resolvedTextSize,
            onContentChange: { frontZone, backZone in
                flashcardDraftContent = FlashcardCardContent(
                    frontZone: frontZone,
                    backZone: backZone,
                    frontType: content.frontType,
                    backType: content.backType
                )
            }
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

    private static func resolvedFlashcardContent(for destination: CardEditorDestination) -> FlashcardCardContent {
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

    private func recordCardEditorLifecycle(_ stage: String) {
        ZoneEditorDebugStore.shared.recordLayoutEvent(
            stage,
            zoneID: destination.draftCard?.id,
            pathID: destination.id,
            details: "kind=\(destination.kind.rawValue) textSize=\(resolvedTextSize.rawValue) search=\(searchQuery == nil ? 0 : 1)"
        )
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
