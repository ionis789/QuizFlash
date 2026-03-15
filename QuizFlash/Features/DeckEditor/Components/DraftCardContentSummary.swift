//
//  DraftCardContentSummary.swift
//  QuizFlash
//
//  Pure content metrics used by the deck editor header and draft-card rows.
//

import Foundation

struct DraftCardContentMetrics: Equatable {
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

    static func +(lhs: DraftCardContentMetrics, rhs: DraftCardContentMetrics) -> DraftCardContentMetrics {
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

struct DraftCardContentSummary: Equatable {
    let front: DraftCardContentMetrics
    let back: DraftCardContentMetrics

    var total: DraftCardContentMetrics {
        front + back
    }

    init(card: DraftCard) {
        self.front = Self.metrics(for: card.frontZone)
        self.back = Self.metrics(for: card.backZone)
    }

    private static func metrics(for zone: ZoneModel) -> DraftCardContentMetrics {
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
}

struct DraftDeckContentSummary: Equatable {
    let cardCount: Int
    let questionZoneCount: Int
    let answerZoneCount: Int
    let characterCount: Int
    let photoCount: Int
    let sketchCount: Int
    let manualCardCount: Int
    let aiCardCount: Int

    init(cards: [DraftCard]) {
        var questionZoneCount = 0
        var answerZoneCount = 0
        var characterCount = 0
        var photoCount = 0
        var sketchCount = 0
        var manualCardCount = 0
        var aiCardCount = 0

        for card in cards {
            let summary = DraftCardContentSummary(card: card)
            questionZoneCount += summary.front.displayZoneCount
            answerZoneCount += summary.back.displayZoneCount
            characterCount += summary.total.textCharacterCount
            photoCount += summary.total.imageCount
            sketchCount += summary.total.sketchCount

            switch card.creationSource {
            case .manual:
                manualCardCount += 1
            case .ai:
                aiCardCount += 1
            }
        }

        self.cardCount = cards.count
        self.questionZoneCount = questionZoneCount
        self.answerZoneCount = answerZoneCount
        self.characterCount = characterCount
        self.photoCount = photoCount
        self.sketchCount = sketchCount
        self.manualCardCount = manualCardCount
        self.aiCardCount = aiCardCount
    }
}
