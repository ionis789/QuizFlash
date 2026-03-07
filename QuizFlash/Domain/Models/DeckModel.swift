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

    /// The SF Symbol name used as the deck's icon.
    var icon: String

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

    // MARK: - Relationships

    /// The folder this deck belongs to. `nil` if the deck is in the root library.
    var folder: FolderModel?

    /// All cards contained in this deck.
    @Relationship(deleteRule: .cascade)
    var cards: [CardModel] = []

    // MARK: - Initializer

    /// Creates a new `DeckModel` with the given display properties.
    ///
    /// - Parameters:
    ///   - title: The display title of the deck.
    ///   - icon: The SF Symbol name for the deck's icon.
    ///   - colorHex: The deck's background colour as a hex string.
    init(title: String, icon: String, colorHex: String) {
        self.title = title
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = Date()
        self.editedAt = Date()
        self.lastAssignedCardNumber = 0
    }
}
