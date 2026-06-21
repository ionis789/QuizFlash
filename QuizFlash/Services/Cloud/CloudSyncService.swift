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

    private var cachedFirestore: Firestore?
    private let encoder: JSONEncoder

    init(firestore: Firestore? = nil) {
        self.cachedFirestore = firestore
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
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
        let cardsRef = deckRef.collection("cards")
        let remoteCards = try await cardsRef.getDocuments()

        deck.cloudID = deckID
        deck.ownerUID = uid
        deck.syncRevision += 1
        deck.lastSyncedAt = now

        var skippedOversizedCard = false
        var currentCardIDs = Set<String>()
        let batch = firestore.batch()
        batch.setData(deckPayload(for: deck), forDocument: deckRef, merge: true)

        for card in cards {
            let cardID = card.cloudID ?? UUID().uuidString
            let payloadData = try encoder.encode(DeckJSONCardDTO.from(content: card.cardContent))
            guard payloadData.count <= Self.safeCardPayloadBytes else {
                skippedOversizedCard = true
                continue
            }

            currentCardIDs.insert(cardID)
            card.cloudID = cardID
            card.ownerUID = uid
            card.syncRevision += 1
            card.lastSyncedAt = now

            let payloadObject = try JSONSerialization.jsonObject(with: payloadData, options: [])
            let cardRef = cardsRef.document(cardID)
            batch.setData(cardPayload(for: card, payloadObject: payloadObject), forDocument: cardRef, merge: true)
        }

        for remoteCard in remoteCards.documents where !currentCardIDs.contains(remoteCard.documentID) {
            batch.setData([
                "deletedAt": Timestamp(date: now),
                "editedAt": Timestamp(date: now),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: remoteCard.reference, merge: true)
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

        try await softDeleteDeck(deckID: cloudID, uid: uid)
    }

    /// Marks one deck deleted without granting client delete permission in Firestore.
    func softDeleteDeck(deckID: String, uid: String) async throws {
        let now = Date()

        try await firestore
            .collection("users")
            .document(uid)
            .collection("decks")
            .document(deckID)
            .setData([
                "deletedAt": Timestamp(date: now),
                "editedAt": Timestamp(date: now),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
    }

    func addDeckListener(
        uid: String,
        listener: @escaping (QuerySnapshot?, Error?) -> Void
    ) -> ListenerRegistration {
        firestore
            .collection("users")
            .document(uid)
            .collection("decks")
            .addSnapshotListener(listener)
    }

    func cards(uid: String, deckID: String) async throws -> [QueryDocumentSnapshot] {
        try await firestore
            .collection("users")
            .document(uid)
            .collection("decks")
            .document(deckID)
            .collection("cards")
            .getDocuments()
            .documents
    }

    private var firestore: Firestore {
        if let cachedFirestore { return cachedFirestore }
        let firestore = Firestore.firestore()
        cachedFirestore = firestore
        return firestore
    }

    private func deckPayload(for deck: DeckModel) -> [String: Any] {
        var payload: [String: Any] = [
            "schemaVersion": DeckJSONDocument.supportedSchemaVersion,
            "title": deck.title,
            "colorHex": deck.colorHex,
            "createdAt": Timestamp(date: deck.createdAt),
            "editedAt": Timestamp(date: deck.editedAt),
            "cardCount": deck.cardCount,
            "lastAssignedCardNumber": deck.lastAssignedCardNumber,
            "syncRevision": deck.syncRevision,
            "notFullySynced": deck.isNotFullySynced,
            "deletedAt": FieldValue.delete(),
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
            "deletedAt": FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }
}
