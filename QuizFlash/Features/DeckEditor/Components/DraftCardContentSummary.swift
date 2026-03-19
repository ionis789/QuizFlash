//
//  DraftCardContentSummary.swift
//  QuizFlash
//
//  Pure content metrics used by the deck editor header and draft-card rows.
//

import Foundation

nonisolated struct DraftCardContentMetrics: Equatable {
    var zoneCount: Int = 0
    var textCharacterCount: Int = 0
    var imageCount: Int = 0
    var sketchCount: Int = 0
    var codeBlockCount: Int = 0
    var filledLeafCount: Int = 0

    var hasContent: Bool {
        filledLeafCount > 0
    }

    var displayZoneCount: Int {
        hasContent ? filledLeafCount : 0
    }

    nonisolated static func +(lhs: DraftCardContentMetrics, rhs: DraftCardContentMetrics) -> DraftCardContentMetrics {
        DraftCardContentMetrics(
            zoneCount: lhs.zoneCount + rhs.zoneCount,
            textCharacterCount: lhs.textCharacterCount + rhs.textCharacterCount,
            imageCount: lhs.imageCount + rhs.imageCount,
            sketchCount: lhs.sketchCount + rhs.sketchCount,
            codeBlockCount: lhs.codeBlockCount + rhs.codeBlockCount,
            filledLeafCount: lhs.filledLeafCount + rhs.filledLeafCount
        )
    }
}

nonisolated struct DraftCardSectionSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let metrics: DraftCardContentMetrics

    init(title: String, symbol: String, metrics: DraftCardContentMetrics) {
        self.id = title.lowercased()
        self.title = title
        self.symbol = symbol
        self.metrics = metrics
    }
}

nonisolated struct DraftCardContentSummary: Equatable {
    let kind: CardKind
    let sections: [DraftCardSectionSummary]

    var total: DraftCardContentMetrics {
        sections.reduce(DraftCardContentMetrics()) { $0 + $1.metrics }
    }

    init(card: DraftCard) {
        kind = card.kind

        switch card.content {
        case .flashcard(let content):
            sections = [
                Self.section(title: "Question", symbol: "q.circle", zones: [content.frontZone]),
                Self.section(title: "Answer", symbol: "a.circle", zones: [content.backZone])
            ]
        case .quiz(let content):
            var resolvedSections = [
                Self.section(title: "Question", symbol: "questionmark.bubble", zones: [content.questionZone]),
                Self.section(title: "Choices", symbol: "checklist", zones: content.choices.map(\.contentZone))
            ]

            if let explanationZone = content.explanationZone {
                resolvedSections.append(
                    Self.section(title: "Explanation", symbol: "text.bubble", zones: [explanationZone])
                )
            }

            sections = resolvedSections
        case .write(let content):
            sections = [
                Self.section(title: "Prompt", symbol: "pencil.line", zones: [content.sourceZone]),
                Self.section(
                    title: "Blank",
                    symbol: "rectangle.and.pencil.and.ellipsis",
                    metrics: Self.metrics(for: content.blankSelection.omittedText)
                )
            ]
        }
    }

    private nonisolated static func section(
        title: String,
        symbol: String,
        zones: [ZoneModel]
    ) -> DraftCardSectionSummary {
        let combinedMetrics = zones
            .map(metrics(for:))
            .reduce(DraftCardContentMetrics(), +)

        return DraftCardSectionSummary(title: title, symbol: symbol, metrics: combinedMetrics)
    }

    private nonisolated static func section(
        title: String,
        symbol: String,
        metrics: DraftCardContentMetrics
    ) -> DraftCardSectionSummary {
        DraftCardSectionSummary(title: title, symbol: symbol, metrics: metrics)
    }

    private nonisolated static func metrics(for zone: ZoneModel) -> DraftCardContentMetrics {
        if zone.isLeaf {
            let trimmedText = zone.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasTrimmedText = !trimmedText.isEmpty

            return DraftCardContentMetrics(
                zoneCount: 1,
                textCharacterCount: hasTrimmedText ? trimmedText.count : 0,
                imageCount: zone.contentType == .image && zone.imageData != nil ? 1 : 0,
                sketchCount: zone.contentType == .sketch && zone.imageData != nil ? 1 : 0,
                codeBlockCount: zone.contentType == .code && hasTrimmedText ? 1 : 0,
                filledLeafCount: zone.hasContent ? 1 : 0
            )
        }

        let childMetrics = zone.children?.map { metrics(for: $0) } ?? []
        return childMetrics.reduce(DraftCardContentMetrics(zoneCount: 1)) { partial, next in
            partial + next
        }
    }

    private nonisolated static func metrics(for text: String) -> DraftCardContentMetrics {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasTrimmedText = !trimmedText.isEmpty

        return DraftCardContentMetrics(
            zoneCount: hasTrimmedText ? 1 : 0,
            textCharacterCount: hasTrimmedText ? trimmedText.count : 0,
            imageCount: 0,
            sketchCount: 0,
            codeBlockCount: 0,
            filledLeafCount: hasTrimmedText ? 1 : 0
        )
    }
}

nonisolated struct DraftDeckContentSummary: Equatable {
    let cardCount: Int
    let flashcardCount: Int
    let quizCount: Int
    let writeCount: Int
    let filledContentBlockCount: Int
    let characterCount: Int
    let photoCount: Int
    let sketchCount: Int
    let manualCardCount: Int
    let aiCardCount: Int

    init(cards: [DraftCard]) {
        var flashcardCount = 0
        var quizCount = 0
        var writeCount = 0
        var filledContentBlockCount = 0
        var characterCount = 0
        var photoCount = 0
        var sketchCount = 0
        var manualCardCount = 0
        var aiCardCount = 0

        for card in cards {
            let summary = DraftCardContentSummary(card: card)
            filledContentBlockCount += summary.total.displayZoneCount
            characterCount += summary.total.textCharacterCount
            photoCount += summary.total.imageCount
            sketchCount += summary.total.sketchCount

            switch card.kind {
            case .flashcard:
                flashcardCount += 1
            case .quiz:
                quizCount += 1
            case .write:
                writeCount += 1
            }

            switch card.creationSource {
            case .manual:
                manualCardCount += 1
            case .ai:
                aiCardCount += 1
            }
        }

        self.cardCount = cards.count
        self.flashcardCount = flashcardCount
        self.quizCount = quizCount
        self.writeCount = writeCount
        self.filledContentBlockCount = filledContentBlockCount
        self.characterCount = characterCount
        self.photoCount = photoCount
        self.sketchCount = sketchCount
        self.manualCardCount = manualCardCount
        self.aiCardCount = aiCardCount
    }
}
