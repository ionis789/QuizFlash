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
    var safeAreaInsets: UIEdgeInsets = .zero
    var searchQuery: String? = nil
    var textSizeOverride: FlashcardTextSize? = nil
    var onSave: (DraftCardContent) -> Void
    @State private var flashcardDraftContent: FlashcardCardContent

    init(
        destination: CardEditorDestination,
        safeAreaInsets: UIEdgeInsets = .zero,
        searchQuery: String? = nil,
        textSizeOverride: FlashcardTextSize? = nil,
        onSave: @escaping (DraftCardContent) -> Void
    ) {
        self.destination = destination
        self.safeAreaInsets = safeAreaInsets
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
        Group {
            switch destination.kind {
            case .flashcard:
                flashcardEditor
            case .quiz:
                quizEditor
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CardEditorRootFramePreferenceKey.self,
                    value: proxy.frame(in: .global)
                )
            }
        }
        .onPreferenceChange(CardEditorRootFramePreferenceKey.self) { frame in
            ZoneEditorDebugStore.shared.recordSheetDismissTrace(
                "card-editor.root-frame",
                details: "destination=\(destination.id) kind=\(destination.kind.rawValue) frame=\(debugRect(frame))"
            )
        }
        .onAppear {
            ZoneEditorDebugStore.shared.recordSheetDismissTrace(
                "card-editor.appear",
                details: "destination=\(destination.id) kind=\(destination.kind.rawValue)"
            )
        }
        .onDisappear {
            ZoneEditorDebugStore.shared.recordSheetDismissTrace(
                "card-editor.disappear",
                details: "destination=\(destination.id) kind=\(destination.kind.rawValue)"
            )
        }
    }

    private var flashcardEditor: some View {
        let content = flashcardDraftContent

        return FlashcardEditorView(
            frontZone: content.frontZone,
            backZone: content.backZone,
            searchQuery: searchQuery,
            textSize: resolvedTextSize,
            safeAreaInsets: safeAreaInsets,
            onContentChange: { frontZone, backZone in
                flashcardDraftContent = FlashcardCardContent(
                    frontZone: frontZone,
                    backZone: backZone,
                    frontType: content.frontType,
                    backType: content.backType
                )
            }
        ) { frontZone, backZone in
            ZoneEditorDebugStore.shared.recordDismissFlow(
                "card-editor.flashcard-onsave.start",
                details: "destination=\(destination.id) kind=\(destination.kind.rawValue)"
            )
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
            ZoneEditorDebugStore.shared.recordDismissFlow(
                "card-editor.flashcard-onsave.end",
                details: "destination=\(destination.id) kind=\(destination.kind.rawValue)"
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
            textSize: resolvedTextSize,
            safeAreaInsets: safeAreaInsets
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

    private func debugRect(_ rect: CGRect) -> String {
        String(
            format: "%.1f,%.1f %.1fx%.1f",
            Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)
        )
    }

}

private struct CardEditorRootFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
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
