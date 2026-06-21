//
//  DeckModel.swift
//  QuizFlash
//
//  A SwiftData model representing a flashcard deck.
//  This file must remain free of SwiftUI and UIKit imports —
//  it is a pure data layer entity.
//

import Foundation
import SwiftData

// MARK: - Deck Card Grouping Mode

/// Controls how `DeckView` sections cards after the active sort order is applied.
nonisolated enum DeckCardGroupingMode: String, Codable, CaseIterable, Sendable {
    case chronological
    case byCardType

    /// Human-readable label shown in deck menus.
    var title: String {
        switch self {
        case .chronological:
            return "By Date"
        case .byCardType:
            return "By Card Type"
        }
    }
}

// MARK: - Deck Model

/// A SwiftData persistent model representing a collection of `CardModel` objects.
///
/// `DeckModel` is a pure data entity. It must not import SwiftUI or UIKit,
/// and must not contain any presentation logic or UI state.
@Model
class DeckModel {

    // MARK: - Properties

    /// The display title of the deck.
    var title: String

    /// The deck's background colour, stored as a hex string (e.g. `"#FF5733"`).
    var colorHex: String

    /// The date this deck was first created.
    var createdAt: Date

    /// The date this deck was last modified.
    var editedAt: Date

    /// The date this deck was last opened by the user. `nil` if never opened.
    var lastOpenedAt: Date?

    /// A monotonically increasing counter used to assign unique sequential numbers to new cards.
    /// Persisted so that card numbers remain stable even after cards are deleted.
    var lastAssignedCardNumber: Int = 0

    /// Denormalised card count — updated whenever cards are added or removed.
    ///
    /// Avoids faulting the `cards` relationship (which permanently retains
    /// **all** `CardModel` objects in the iOS 17 `ModelContext` row cache) just
    /// to read `.count`. Always keep this value in sync with `cards.count`.
    var cardCount: Int = 0

    /// Raw string backing the persisted card grouping preference for this deck.
    var cardGroupingModeRaw: String = DeckCardGroupingMode.chronological.rawValue

    /// Stable Firestore document ID for cloud sync. Nil until the deck is uploaded.
    var cloudID: String?

    /// Firebase Auth UID that owns the cloud copy of this deck.
    var ownerUID: String?

    /// Last successful cloud sync timestamp.
    var lastSyncedAt: Date?

    /// Monotonic local sync revision used by v1 last-write-wins sync.
    var syncRevision: Int = 0

    /// True when at least one card payload was skipped because it exceeded the v1 safe sync size.
    var isNotFullySynced: Bool = false

    // MARK: - Relationships

    /// The folder this deck belongs to. `nil` if the deck is in the root library.
    var folder: FolderModel?

    /// All cards contained in this deck.
    @Relationship(deleteRule: .cascade)
    var cards: [CardModel] = []

    /// Persisted play-mode settings scoped to this specific deck.
    @Relationship(deleteRule: .cascade, inverse: \DeckPlayModeSettingsModel.deck)
    var playModeSettings: DeckPlayModeSettingsModel?

    /// The persisted grouping preference used by `DeckView`.
    var cardGroupingMode: DeckCardGroupingMode {
        get { DeckCardGroupingMode(rawValue: cardGroupingModeRaw) ?? .chronological }
        set { cardGroupingModeRaw = newValue.rawValue }
    }

    // MARK: - Initializer

    /// Creates a new `DeckModel` with the given display properties.
    ///
    /// - Parameters:
    ///   - title: The display title of the deck.
    ///   - colorHex: The deck's background colour as a hex string.
    init(title: String, colorHex: String) {
        self.title = title
        self.colorHex = colorHex
        self.createdAt = Date()
        self.editedAt = Date()
        self.lastAssignedCardNumber = 0
        self.cardGroupingModeRaw = DeckCardGroupingMode.chronological.rawValue
        self.playModeSettings = nil
        self.syncRevision = 0
        self.isNotFullySynced = false
    }
}
