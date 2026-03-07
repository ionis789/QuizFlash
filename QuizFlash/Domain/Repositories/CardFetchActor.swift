//
//  CardFetchActor.swift
//  QuizFlash
//

import SwiftUI
import SwiftData

// MARK: - Global DeckStats
// Mutat aici pentru a fi vizibil global și pentru a respecta standardul Sendable (Safe Concurrency)
struct DeckStats: Sendable {
    let totalCards: Int
    let dueCards: Int
    let totalReviews: Int
    let accuracy: Int
    let totalXPEarned: Int
    let deckMastery: Double
    let todayReviewed: Int

    static let empty = DeckStats(
        totalCards: 0, dueCards: 0, totalReviews: 0,
        accuracy: 0, totalXPEarned: 0, deckMastery: 0.0, todayReviewed: 0
    )
}

// MARK: - CardDataSnapshot
struct CardDataSnapshot: Sendable {
    let gridCards: [GridCardInfo]
    let stats: DeckStats
}

// MARK: - CardFetchActor
actor CardFetchActor {

    // Salvăm container-ul pentru a putea recrea contextul oricând
    private let container: ModelContainer
    private var activeContext: ModelContext

    init(container: ModelContainer) {
        self.container = container
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        self.activeContext = ctx
    }

    /// 🔥 FIX iOS 17: Golirea Memoriei Cache
    /// Deoarece SwiftData nu are funcția `.reset()`, distrugem fizic contextul vechi
    /// și inițializăm unul nou. Orice card de 2MB reținut în vechiul context este dealocat instantaneu.
    private func flushRAM() {
        let freshContext = ModelContext(container)
        freshContext.autosaveEnabled = false
        self.activeContext = freshContext
    }

    // MARK: - Card Snapshot

    func fetchSnapshot(deckID: PersistentIdentifier) -> CardDataSnapshot {
        guard let deck = activeContext.model(for: deckID) as? DeckModel else {
            return CardDataSnapshot(gridCards: [], stats: .empty)
        }

        let now        = Date()
        let todayStart = Calendar.current.startOfDay(for: now)
        var gridCards  = [GridCardInfo]()
        var accum      = StatsAccumulator()
        
        // Fetch directly from the SQLite store using a predicate. This bypasses
        // the `deck.cards` relationship array, which is prone to caching bugs on iOS 17
        // where it fails to reflect newly inserted cards across different contexts.
        let descriptor = FetchDescriptor<CardModel>(
            predicate: #Predicate { $0.deck?.persistentModelID == deckID }
        )
        let cards = (try? activeContext.fetch(descriptor)) ?? []

        for card in cards {
            gridCards.append(GridCardInfo(
                id:                   card.persistentModelID,
                cardNumber:           card.cardNumber,
                interval:             card.interval,
                reviewHistoryIsEmpty: card.reviewHistory.isEmpty,
                frontText:            card.frontText,
                backText:             card.backText,
                createdAt:            card.createdAt,
                editedAt:             card.editedAt
            ))
            accum.accumulate(card: card, now: now, todayStart: todayStart)
        }

        // Dealocăm cardurile grele din RAM imediat după ce am creat structurile ușoare GridCardInfo
        flushRAM()

        return CardDataSnapshot(
            gridCards: gridCards,
            stats:     accum.build(count: gridCards.count)
        )
    }

    // MARK: - Thumbnail Generation

    func generateThumbnail(for id: PersistentIdentifier) -> CardPreviewPayload? {
        guard let card = activeContext.model(for: id) as? CardModel else { return nil }

        let frontData = card.frontZoneData
        let backData  = card.backZoneData

        // Evacuăm baza de date din RAM înainte să stresăm procesorul cu decodarea imaginilor
        flushRAM()

        let frontZone = frontData.flatMap { ZoneModel.decode(from: $0) }
        let backZone  = backData.flatMap  { ZoneModel.decode(from: $0) }

        let rawImageData = frontZone.flatMap { getFirstImageData(from: $0) }
                        ?? backZone.flatMap  { getFirstImageData(from: $0) }

        let thumbData = rawImageData.flatMap { raw -> Data? in
            let maxPx: CGFloat = 88 * 3
            return downsample(data: raw, maxDimension: maxPx)
                .flatMap { $0.jpegData(compressionQuality: 0.6) }
        }

        return CardPreviewPayload(
            thumbnailData:  thumbData,
            hasFrontImage:  frontZone.map { containsMedia($0, contentType: .image)  } ?? false,
            hasFrontSketch: frontZone.map { containsMedia($0, contentType: .sketch) } ?? false
        )
    }

    // MARK: - Lifecycle

    func tearDown() {
        // Omorâm contextul definitiv înainte de a fi curățat de Garbage Collector
        flushRAM()
    }
}

// MARK: - StatsAccumulator

private struct StatsAccumulator {
    var totalReviews   = 0
    var correctReviews = 0
    var totalXP        = 0
    var dueCards       = 0
    var masterySum     = 0.0
    var todayReviewed  = 0

    mutating func accumulate(card: CardModel, now: Date, todayStart: Date) {
        let history     = card.reviewHistory
        totalReviews   += history.count
        correctReviews += history.filter { $0.difficultyRaw >= ReviewDifficulty.good.rawValue }.count
        totalXP        += history.reduce(0) { $0 + $1.xpAwarded }
        if card.dueDate <= now { dueCards += 1 }
        todayReviewed  += history.filter { $0.timestamp >= todayStart }.count
        masterySum     += Self.masteryScore(for: card)
    }

    func build(count: Int) -> DeckStats {
        DeckStats(
            totalCards:    count,
            dueCards:      dueCards,
            totalReviews:  totalReviews,
            accuracy:      totalReviews > 0
                ? Int(Double(correctReviews) / Double(totalReviews) * 100) : 0,
            totalXPEarned: totalXP,
            deckMastery:   count > 0 ? masterySum / Double(count) : 0.0,
            todayReviewed: todayReviewed
        )
    }

    private static func masteryScore(for card: CardModel) -> Double {
        guard !card.reviewHistory.isEmpty else { return 0.0 }
        switch card.interval {
        case 0:       return 0.10
        case 1:       return 0.15
        case 2...3:   return 0.25
        case 4...6:   return 0.40
        case 7...10:  return 0.58
        case 11...14: return 0.70
        case 15...20: return 0.82
        default:
            let easeNorm = (card.easeFactor - 1.3) / (2.5 - 1.3)
            return min(0.90 + easeNorm * 0.10, 1.0)
        }
    }
}
