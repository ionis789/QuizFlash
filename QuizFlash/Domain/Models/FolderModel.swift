//
//  FolderModel.swift
//  QuizFlash
//
//  A SwiftData model representing a folder that groups flashcard decks.
//  This file must remain free of SwiftUI and UIKit imports —
//  it is a pure data layer entity.
//

import Foundation
import SwiftData

// MARK: - Folder Model

/// A SwiftData persistent model representing a named folder that groups `DeckModel` objects.
///
/// `FolderModel` is a pure data entity. It must not import SwiftUI or UIKit,
/// and must not contain any presentation logic or UI state.
@Model
class FolderModel {

    // MARK: - Properties

    /// A stable unique identifier for this folder (separate from the `PersistentIdentifier`).
    var id: UUID = UUID()

    /// The display title of the folder.
    var title: String

    /// The folder's accent colour, stored as a hex string (e.g. `"#34C759"`).
    var colorHex: String

    /// Denormalised deck count — updated whenever decks are added to or removed from this folder.
    ///
    /// Avoids faulting the `decks` relationship just to read `.count`.
    /// Always keep this value in sync with `decks.count`.
    var deckCount: Int = 0

    /// The date this folder was first created.
    var createdAt: Date

    /// The date this folder was last modified.
    var editedAt: Date = Date()

    /// Stable Firestore document ID for cloud sync. Nil until the folder is uploaded.
    var cloudID: String?

    /// Firebase Auth UID that owns the cloud copy of this folder.
    var ownerUID: String?

    /// Last successful cloud sync timestamp.
    var lastSyncedAt: Date?

    /// Monotonic local sync revision used by v1 last-write-wins sync.
    var syncRevision: Int = 0

    // MARK: - Relationships

    /// All decks contained in this folder.
    ///
    /// Deleting a folder **nullifies** the relationship on each deck,
    /// moving them back to the root "All Decks" view rather than cascade-deleting them.
    @Relationship(deleteRule: .nullify, inverse: \DeckModel.folder)
    var decks: [DeckModel] = []

    // MARK: - Initializer

    /// Creates a new `FolderModel` with the given display properties.
    ///
    /// - Parameters:
    ///   - title: The display title of the folder.
    ///   - colorHex: The folder's accent colour as a hex string.
    init(title: String, colorHex: String) {
        self.title = title
        self.colorHex = colorHex
        self.deckCount = 0
        let now = Date()
        self.createdAt = now
        self.editedAt = now
        self.syncRevision = 0
    }
}
