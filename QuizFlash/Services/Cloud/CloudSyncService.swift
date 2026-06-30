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
        cards: [CardModel],
        dailyStudyAggregates: [HomeDailyStudyAggregate] = [],
        dailyDeckAggregates: [HomeDailyDeckAggregate] = [],
        dailyCardAggregates: [HomeDailyCardAggregate] = []
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
        let userRef = firestore
            .collection("users")
            .document(uid)

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

            for event in card.reviewHistory {
                let eventID = event.cloudID ?? UUID().uuidString
                event.cloudID = eventID
                event.ownerUID = uid
                event.lastSyncedAt = now

                batch.setData(
                    reviewEventPayload(for: event),
                    forDocument: cardRef.collection("reviewEvents").document(eventID),
                    merge: true
                )
            }
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

        for aggregate in dailyStudyAggregates {
            batch.setData(
                dailyStudyPayload(for: aggregate),
                forDocument: userRef.collection("homeDailyStudy").document(aggregate.dayKey),
                merge: true
            )
        }

        for aggregate in dailyDeckAggregates {
            batch.setData(
                dailyDeckPayload(for: aggregate),
                forDocument: userRef.collection("homeDailyDecks").document(aggregate.aggregateKey),
                merge: true
            )
        }

        for aggregate in dailyCardAggregates {
            batch.setData(
                dailyCardPayload(for: aggregate),
                forDocument: userRef.collection("homeDailyCards").document(aggregate.aggregateKey),
                merge: true
            )
        }

        try await batch.commit()
    }

    /// Uploads a folder document.
    func upsertFolder(_ folder: FolderModel, uid: String) async throws {
        let folderID = folder.cloudID ?? UUID().uuidString
        let now = Date()
        let folderRef = firestore
            .collection("users")
            .document(uid)
            .collection("folders")
            .document(folderID)

        folder.cloudID = folderID
        folder.ownerUID = uid
        folder.syncRevision += 1
        folder.lastSyncedAt = now

        try await folderRef.setData(folderPayload(for: folder), merge: true)
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

    /// Marks one folder deleted without granting client delete permission in Firestore.
    func softDeleteFolder(folderID: String, uid: String) async throws {
        let now = Date()

        try await firestore
            .collection("users")
            .document(uid)
            .collection("folders")
            .document(folderID)
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

    func addFolderListener(
        uid: String,
        listener: @escaping (QuerySnapshot?, Error?) -> Void
    ) -> ListenerRegistration {
        firestore
            .collection("users")
            .document(uid)
            .collection("folders")
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

    func reviewEvents(uid: String, deckID: String, cardID: String) async throws -> [QueryDocumentSnapshot] {
        try await firestore
            .collection("users")
            .document(uid)
            .collection("decks")
            .document(deckID)
            .collection("cards")
            .document(cardID)
            .collection("reviewEvents")
            .getDocuments()
            .documents
    }

    func homeAnalytics(uid: String, collectionID: String) async throws -> [QueryDocumentSnapshot] {
        try await firestore
            .collection("users")
            .document(uid)
            .collection(collectionID)
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
        if let folderID = deck.folder?.cloudID {
            payload["folderID"] = folderID
        } else {
            payload["folderID"] = FieldValue.delete()
        }
        if let lastOpenedAt = deck.lastOpenedAt {
            payload["lastOpenedAt"] = Timestamp(date: lastOpenedAt)
        }
        return payload
    }

    private func folderPayload(for folder: FolderModel) -> [String: Any] {
        [
            "schemaVersion": 1,
            "title": folder.title,
            "colorHex": folder.colorHex,
            "deckCount": folder.deckCount,
            "createdAt": Timestamp(date: folder.createdAt),
            "editedAt": Timestamp(date: folder.editedAt),
            "syncRevision": folder.syncRevision,
            "deletedAt": FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
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
            "dueDate": Timestamp(date: card.dueDate),
            "easeFactor": card.easeFactor,
            "interval": card.interval,
            "consecutiveCorrectAnswers": card.consecutiveCorrectAnswers,
            "syncRevision": card.syncRevision,
            "payload": payloadObject,
            "deletedAt": FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }

    private func reviewEventPayload(for event: ReviewEvent) -> [String: Any] {
        [
            "timestamp": Timestamp(date: event.timestamp),
            "timeSpent": event.timeSpent,
            "difficultyRaw": event.difficultyRaw,
            "xpAwarded": event.xpAwarded,
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }

    private func dailyStudyPayload(for aggregate: HomeDailyStudyAggregate) -> [String: Any] {
        [
            "dayKey": aggregate.dayKey,
            "dayDate": Timestamp(date: aggregate.dayDate),
            "uniqueCardCount": aggregate.uniqueCardCount,
            "rawReviewCount": aggregate.rawReviewCount,
            "landedCount": aggregate.landedCount,
            "retryCount": aggregate.retryCount,
            "xpEarned": aggregate.xpEarned,
            "newCardsLearned": aggregate.newCardsLearned,
            "dailyGoal": aggregate.dailyGoal,
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }

    private func dailyDeckPayload(for aggregate: HomeDailyDeckAggregate) -> [String: Any] {
        [
            "aggregateKey": aggregate.aggregateKey,
            "dayKey": aggregate.dayKey,
            "dayDate": Timestamp(date: aggregate.dayDate),
            "deckIdentifier": aggregate.deckIdentifier,
            "deckTitleSnapshot": aggregate.deckTitleSnapshot,
            "deckColorHexSnapshot": aggregate.deckColorHexSnapshot,
            "uniqueCardCount": aggregate.uniqueCardCount,
            "landedCount": aggregate.landedCount,
            "retryCount": aggregate.retryCount,
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }

    private func dailyCardPayload(for aggregate: HomeDailyCardAggregate) -> [String: Any] {
        [
            "aggregateKey": aggregate.aggregateKey,
            "dayKey": aggregate.dayKey,
            "dayDate": Timestamp(date: aggregate.dayDate),
            "cardIdentifier": aggregate.cardIdentifier,
            "deckIdentifier": aggregate.deckIdentifier,
            "deckAggregateKey": aggregate.deckAggregateKey,
            "deckTitleSnapshot": aggregate.deckTitleSnapshot,
            "deckColorHexSnapshot": aggregate.deckColorHexSnapshot,
            "cardTitleSnapshot": aggregate.cardTitleSnapshot,
            "finalDifficultyRaw": aggregate.finalDifficultyRaw,
            "repeatCount": aggregate.repeatCount,
            "lastReviewedAt": Timestamp(date: aggregate.lastReviewedAt),
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }
}
