//
//  CloudSyncCoordinator.swift
//  QuizFlash
//

import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import Observation
import SwiftData

// MARK: - Cloud Sync Coordinator

/// Coordinates durable background deck sync without delaying local SwiftData saves.
@Observable
@MainActor
final class CloudSyncCoordinator {
    static let shared = CloudSyncCoordinator()

    @ObservationIgnored private let service: CloudSyncService
    @ObservationIgnored private let outbox: CloudSyncOutbox
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?

    private(set) var activeUID: String?
    private(set) var lastErrorMessage: String?

    init(
        service: CloudSyncService? = nil,
        outbox: CloudSyncOutbox = CloudSyncOutbox()
    ) {
        self.service = service ?? .shared
        self.outbox = outbox
    }

    // MARK: - Session

    /// Starts background sync for one signed-in Firebase user.
    func configure(for user: AuthUserSnapshot?, modelContainer: ModelContainer) {
        stop()
        guard let user else { return }

        activeUID = user.uid
        self.modelContainer = modelContainer
        listener = service.addDeckListener(uid: user.uid) { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                self?.handleRemoteSnapshot(snapshot, error: error)
            }
        }
        scheduleOutboxProcessing()
    }

    func stop() {
        listener?.remove()
        listener = nil
        processingTask?.cancel()
        processingTask = nil
        retryTask?.cancel()
        retryTask = nil
        activeUID = nil
        modelContainer = nil
        lastErrorMessage = nil
    }

    // MARK: - Local Mutations

    /// Assigns stable cloud IDs before a newly created deck is first saved.
    func assignCloudIdentityIfPossible(to deck: DeckModel) {
        guard let uid = currentUserID() else { return }
        assignCloudIdentity(to: deck, uid: uid)
    }

    /// Queues an upsert after local persistence has completed successfully.
    func enqueueUpsert(for deck: DeckModel, context: ModelContext) {
        guard let uid = currentUserID() else { return }
        assignCloudIdentity(to: deck, uid: uid)

        do {
            try context.save()
        } catch {
            lastErrorMessage = error.localizedDescription
            return
        }

        guard let deckID = deck.cloudID else { return }
        Task { [weak self, outbox] in
            do {
                try await outbox.enqueue(ownerUID: uid, deckID: deckID, kind: .upsertDeck)
                self?.scheduleOutboxProcessing()
            } catch {
                self?.record(error)
            }
        }
    }

    /// Queues a cloud tombstone before the caller removes a local deck.
    func enqueueDelete(for deck: DeckModel) {
        guard let uid = currentUserID(), deck.ownerUID == uid, let deckID = deck.cloudID else { return }

        Task { [weak self, outbox] in
            do {
                try await outbox.enqueue(ownerUID: uid, deckID: deckID, kind: .deleteDeck)
                self?.scheduleOutboxProcessing()
            } catch {
                self?.record(error)
            }
        }
    }

    // MARK: - Outbox

    private func scheduleOutboxProcessing() {
        guard processingTask == nil else { return }

        processingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await processOutbox()
            processingTask = nil
        }
    }

    private func processOutbox() async {
        guard let uid = activeUID, let modelContainer else { return }

        do {
            let operations = try await outbox.operations(for: uid)
            guard !operations.isEmpty else { return }

            let context = ModelContext(modelContainer)
            for operation in operations {
                guard !Task.isCancelled else { return }

                do {
                    switch operation.kind {
                    case .upsertDeck:
                        // Cloud IDs are optional in the SwiftData schema, but required for synced decks.
                        guard let deck = try context.fetch(FetchDescriptor<DeckModel>()).first(where: {
                            $0.ownerUID == uid && $0.cloudID == operation.deckID
                        }) else {
                            try await outbox.remove(operation)
                            continue
                        }
                        try await service.upsertDeck(deck, uid: uid, cards: deck.cards)
                        try context.save()
                    case .deleteDeck:
                        try await service.softDeleteDeck(deckID: operation.deckID, uid: uid)
                    }

                    try await outbox.remove(operation)
                    lastErrorMessage = nil
                } catch {
                    lastErrorMessage = error.localizedDescription
                    scheduleRetry()
                    return
                }
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil, activeUID != nil else { return }

        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.retryTask = nil
            self?.scheduleOutboxProcessing()
        }
    }

    // MARK: - Remote Changes

    private func handleRemoteSnapshot(_ snapshot: QuerySnapshot?, error: Error?) {
        if let error {
            lastErrorMessage = error.localizedDescription
            return
        }
        guard let snapshot else { return }

        for change in snapshot.documentChanges where change.type != .removed {
            Task { @MainActor [weak self] in
                await self?.applyRemoteDeck(change.document)
            }
        }
    }

    private func applyRemoteDeck(_ document: QueryDocumentSnapshot) async {
        guard let uid = activeUID, let modelContainer else { return }
        let deckID = document.documentID

        do {
            if try await outbox.containsDelete(ownerUID: uid, deckID: deckID) { return }

            let context = ModelContext(modelContainer)
            let localDeck = try context.fetch(FetchDescriptor<DeckModel>()).first(where: {
                $0.ownerUID == uid && $0.cloudID == deckID
            })
            let data = document.data()
            let remoteEditedAt = date(in: data, key: "editedAt") ?? .distantPast

            if data["deletedAt"] != nil {
                guard let localDeck else { return }
                if localDeck.editedAt > remoteEditedAt {
                    enqueueUpsert(for: localDeck, context: context)
                } else {
                    context.delete(localDeck)
                    try context.save()
                }
                return
            }

            let deck: DeckModel
            if let localDeck {
                if localDeck.editedAt > remoteEditedAt {
                    enqueueUpsert(for: localDeck, context: context)
                    return
                }
                deck = localDeck
            } else {
                deck = DeckModel(
                    title: data["title"] as? String ?? "",
                    colorHex: data["colorHex"] as? String ?? "#FFFFFF"
                )
                deck.ownerUID = uid
                deck.cloudID = deckID
                context.insert(deck)
            }

            deck.title = data["title"] as? String ?? deck.title
            deck.colorHex = data["colorHex"] as? String ?? deck.colorHex
            deck.createdAt = date(in: data, key: "createdAt") ?? deck.createdAt
            deck.editedAt = remoteEditedAt
            deck.lastOpenedAt = date(in: data, key: "lastOpenedAt")
            deck.lastAssignedCardNumber = data["lastAssignedCardNumber"] as? Int ?? deck.lastAssignedCardNumber
            deck.syncRevision = data["syncRevision"] as? Int ?? deck.syncRevision
            deck.isNotFullySynced = data["notFullySynced"] as? Bool ?? false
            deck.lastSyncedAt = Date()

            let remoteCards = try await service.cards(uid: uid, deckID: deckID)
            var shouldUploadLocal = false

            for remoteCard in remoteCards {
                let cardData = remoteCard.data()
                let cardID = remoteCard.documentID
                let remoteCardEditedAt = date(in: cardData, key: "editedAt") ?? .distantPast
                let localCard = deck.cards.first { $0.cloudID == cardID && $0.ownerUID == uid }

                if cardData["deletedAt"] != nil {
                    if let localCard, localCard.editedAt > remoteCardEditedAt {
                        shouldUploadLocal = true
                    } else if let localCard {
                        context.delete(localCard)
                    }
                    continue
                }

                let content = try cardContent(from: cardData)
                if let localCard {
                    if localCard.editedAt > remoteCardEditedAt {
                        shouldUploadLocal = true
                        continue
                    }
                    applyRemoteCard(
                        localCard,
                        content: content,
                        data: cardData,
                        editedAt: remoteCardEditedAt
                    )
                } else {
                    let card = CardModel(
                        content: content,
                        cardNumber: cardData["cardNumber"] as? Int ?? 0,
                        isPinned: cardData["isPinned"] as? Bool ?? false,
                        creationSource: CardCreationSource(rawValue: cardData["creationSource"] as? String ?? "") ?? .manual
                    )
                    card.ownerUID = uid
                    card.cloudID = cardID
                    applyRemoteCard(
                        card,
                        content: content,
                        data: cardData,
                        editedAt: remoteCardEditedAt
                    )
                    card.deck = deck
                    deck.cards.append(card)
                    context.insert(card)
                }
            }

            deck.cardCount = deck.cards.count
            try context.save()
            if shouldUploadLocal { enqueueUpsert(for: deck, context: context) }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func applyRemoteCard(
        _ card: CardModel,
        content: DraftCardContent,
        data: [String: Any],
        editedAt: Date
    ) {
        card.cardContent = content
        card.cardNumber = data["cardNumber"] as? Int ?? card.cardNumber
        card.isPinned = data["isPinned"] as? Bool ?? card.isPinned
        card.creationSourceRaw = data["creationSource"] as? String ?? card.creationSourceRaw
        card.createdAt = date(in: data, key: "createdAt") ?? card.createdAt
        card.editedAt = editedAt
        card.syncRevision = data["syncRevision"] as? Int ?? card.syncRevision
        card.lastSyncedAt = Date()
    }

    // MARK: - Helpers

    private func currentUserID() -> String? {
        guard FirebaseApp.app() != nil else { return nil }
        guard let uid = Auth.auth().currentUser?.uid, uid == activeUID else { return nil }
        return uid
    }

    private func assignCloudIdentity(to deck: DeckModel, uid: String) {
        deck.ownerUID = uid
        if deck.cloudID == nil { deck.cloudID = UUID().uuidString }

        for card in deck.cards {
            card.ownerUID = uid
            if card.cloudID == nil { card.cloudID = UUID().uuidString }
        }
    }

    private func cardContent(from data: [String: Any]) throws -> DraftCardContent {
        guard let payload = data["payload"], JSONSerialization.isValidJSONObject(payload) else {
            throw CloudSyncDecodingError.invalidCardPayload
        }
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(DeckJSONCardDTO.self, from: payloadData).draftCardContent()
    }

    private func date(in data: [String: Any], key: String) -> Date? {
        if let timestamp = data[key] as? Timestamp { return timestamp.dateValue() }
        return data[key] as? Date
    }

    private func record(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }
}

// MARK: - Cloud Sync Decoding Error

enum CloudSyncDecodingError: LocalizedError {
    case invalidCardPayload

    var errorDescription: String? {
        switch self {
        case .invalidCardPayload:
            return "The cloud card payload is invalid."
        }
    }
}
