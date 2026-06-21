//
//  CloudSyncService.swift
//  QuizFlash
//

import FirebaseFirestore
import Foundation
import SwiftData

// MARK: - Cloud Sync Service

/// Firestore v1 deck sync using last-write-wins on `editedAt`.
@MainActor
final class CloudSyncService {
    static let shared = CloudSyncService()
    static let safeCardPayloadBytes = 750_000

    private let firestore: Firestore
    private let encoder: JSONEncoder

    init(firestore: Firestore = Firestore.firestore()) {
        self.firestore = firestore
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    /// Uploads every local deck once for a newly signed-in user.
    func migrateLocalDecksIfNeeded(
        uid: String,
        decks: [DeckModel]
    ) async throws {
        let userRef = firestore.collection("users").document(uid)
        let userSnapshot = try await userRef.getDocument()
        if userSnapshot.data()?["initialMigrationCompleted"] as? Bool == true {
            return
        }

        for deck in decks {
            try await upsertDeck(deck, uid: uid, cards: deck.cards)
        }

        try await userRef.setData([
            "initialMigrationCompleted": true,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    /// Uploads a deck document and its card subcollection.
    func upsertDeck(
        _ deck: DeckModel,
        uid: String,
        cards: [CardModel]
    ) async throws {
        let deckID = deck.cloudID ?? UUID().uuidString
        let now = Date()
        let deckRef = firestore
            .collection("users")
            .document(uid)
            .collection("decks")
            .document(deckID)

        deck.cloudID = deckID
        deck.ownerUID = uid
        deck.syncRevision += 1
        deck.lastSyncedAt = now

        var skippedOversizedCard = false
        let batch = firestore.batch()
        batch.setData(deckPayload(for: deck), forDocument: deckRef, merge: true)

        for card in cards {
            let cardID = card.cloudID ?? UUID().uuidString
            let payloadData = try encoder.encode(DeckJSONCardDTO.from(content: card.cardContent))
            guard payloadData.count <= Self.safeCardPayloadBytes else {
                skippedOversizedCard = true
                continue
            }

            card.cloudID = cardID
            card.ownerUID = uid
            card.syncRevision += 1
            card.lastSyncedAt = now

            let payloadObject = try JSONSerialization.jsonObject(with: payloadData, options: [])
            let cardRef = deckRef.collection("cards").document(cardID)
            batch.setData(cardPayload(for: card, payloadObject: payloadObject), forDocument: cardRef, merge: true)
        }

        deck.isNotFullySynced = skippedOversizedCard
        if skippedOversizedCard {
            batch.setData(["notFullySynced": true], forDocument: deckRef, merge: true)
        }

        try await batch.commit()
    }

    /// Soft-deletes the cloud copy of a deck.
    func softDeleteDeck(_ deck: DeckModel, uid: String) async throws {
        guard let cloudID = deck.cloudID else { return }

        try await firestore
            .collection("users")
            .document(uid)
            .collection("decks")
            .document(cloudID)
            .setData([
                "deletedAt": Timestamp(date: Date()),
                "syncRevision": deck.syncRevision + 1
            ], merge: true)
    }

    private func deckPayload(for deck: DeckModel) -> [String: Any] {
        var payload: [String: Any] = [
            "schemaVersion": DeckJSONDocument.supportedSchemaVersion,
            "title": deck.title,
            "colorHex": deck.colorHex,
            "createdAt": Timestamp(date: deck.createdAt),
            "editedAt": Timestamp(date: deck.editedAt),
            "cardCount": deck.cardCount,
            "syncRevision": deck.syncRevision,
            "notFullySynced": deck.isNotFullySynced,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let lastOpenedAt = deck.lastOpenedAt {
            payload["lastOpenedAt"] = Timestamp(date: lastOpenedAt)
        }
        return payload
    }

    private func cardPayload(
        for card: CardModel,
        payloadObject: Any
    ) -> [String: Any] {
        [
            "schemaVersion": DeckJSONDocument.supportedSchemaVersion,
            "creationSource": card.creationSource.rawValue,
            "createdAt": Timestamp(date: card.createdAt),
            "editedAt": Timestamp(date: card.editedAt),
            "cardNumber": card.cardNumber,
            "isPinned": card.isPinned,
            "syncRevision": card.syncRevision,
            "payload": payloadObject,
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }
}
