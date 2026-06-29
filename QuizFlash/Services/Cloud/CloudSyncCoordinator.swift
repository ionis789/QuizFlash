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
    nonisolated static let editTimestampTolerance: TimeInterval = 0.001

    @ObservationIgnored private let service: CloudSyncService
    @ObservationIgnored private let outbox: CloudSyncOutbox
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var remoteImportActor: CloudSyncRemoteImportActor?
    @ObservationIgnored private var remoteImportTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRemoteDecks: [CloudSyncRemoteDeckHeader] = []

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
        remoteImportActor = CloudSyncRemoteImportActor(container: modelContainer, outbox: outbox)
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
        remoteImportTask?.cancel()
        remoteImportTask = nil
        remoteImportActor = nil
        pendingRemoteDecks.removeAll()
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

        let changedDecks = snapshot.documentChanges
            .filter { $0.type != .removed }
            .map { CloudSyncRemoteDeckHeader(document: $0.document) }
        guard !changedDecks.isEmpty else { return }

        pendingRemoteDecks.append(contentsOf: changedDecks)
        scheduleRemoteImportProcessing()
    }

    private func scheduleRemoteImportProcessing() {
        guard remoteImportTask == nil else { return }

        remoteImportTask = Task { @MainActor [weak self] in
            await self?.processPendingRemoteDecks()
            self?.remoteImportTask = nil
        }
    }

    private func processPendingRemoteDecks() async {
        while !pendingRemoteDecks.isEmpty {
            guard !Task.isCancelled else { return }
            guard let uid = activeUID, let remoteImportActor else { return }

            let header = pendingRemoteDecks.removeFirst()

            do {
                let result = try await remoteImportActor.applyRemoteDeck(header, uid: uid)
                if case .enqueueLocalUpsert(let deckID) = result {
                    try await outbox.enqueue(ownerUID: uid, deckID: deckID, kind: .upsertDeck)
                    scheduleOutboxProcessing()
                }
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
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

    private func record(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }

    /// Ignores sub-millisecond timestamp drift introduced by Firestore serialization.
    nonisolated static func localEditIsMeaningfullyNewer(_ local: Date, than remote: Date) -> Bool {
        local.timeIntervalSince(remote) > editTimestampTolerance
    }
}

// MARK: - Cloud Sync Remote Import

nonisolated enum CloudSyncRemoteImportResult: Equatable, Sendable {
    case noUploadNeeded
    case enqueueLocalUpsert(deckID: String)
}

nonisolated struct CloudSyncRemoteDeckHeader: Sendable {
    let deckID: String
    let title: String
    let colorHex: String
    let createdAt: Date?
    let editedAt: Date
    let lastOpenedAt: Date?
    let lastAssignedCardNumber: Int?
    let syncRevision: Int?
    let isNotFullySynced: Bool
    let isDeleted: Bool

    init(
        deckID: String,
        title: String,
        colorHex: String,
        createdAt: Date?,
        editedAt: Date,
        lastOpenedAt: Date?,
        lastAssignedCardNumber: Int?,
        syncRevision: Int?,
        isNotFullySynced: Bool,
        isDeleted: Bool
    ) {
        self.deckID = deckID
        self.title = title
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.lastOpenedAt = lastOpenedAt
        self.lastAssignedCardNumber = lastAssignedCardNumber
        self.syncRevision = syncRevision
        self.isNotFullySynced = isNotFullySynced
        self.isDeleted = isDeleted
    }

    init(document: QueryDocumentSnapshot) {
        let data = document.data()
        self.init(
            deckID: document.documentID,
            title: data["title"] as? String ?? "",
            colorHex: data["colorHex"] as? String ?? "#FFFFFF",
            createdAt: Self.date(in: data, key: "createdAt"),
            editedAt: Self.date(in: data, key: "editedAt") ?? .distantPast,
            lastOpenedAt: Self.date(in: data, key: "lastOpenedAt"),
            lastAssignedCardNumber: data["lastAssignedCardNumber"] as? Int,
            syncRevision: data["syncRevision"] as? Int,
            isNotFullySynced: data["notFullySynced"] as? Bool ?? false,
            isDeleted: data["deletedAt"] != nil
        )
    }

    private static func date(in data: [String: Any], key: String) -> Date? {
        if let timestamp = data[key] as? Timestamp { return timestamp.dateValue() }
        return data[key] as? Date
    }
}

nonisolated struct CloudSyncRemoteCardSnapshot: Sendable {
    let cardID: String
    let content: DraftCardContent?
    let cardNumber: Int
    let isPinned: Bool
    let creationSourceRaw: String
    let createdAt: Date?
    let editedAt: Date
    let syncRevision: Int?
    let isDeleted: Bool

    init(
        cardID: String,
        content: DraftCardContent?,
        cardNumber: Int,
        isPinned: Bool,
        creationSourceRaw: String,
        createdAt: Date?,
        editedAt: Date,
        syncRevision: Int?,
        isDeleted: Bool
    ) {
        self.cardID = cardID
        self.content = content
        self.cardNumber = cardNumber
        self.isPinned = isPinned
        self.creationSourceRaw = creationSourceRaw
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.syncRevision = syncRevision
        self.isDeleted = isDeleted
    }

    init(document: QueryDocumentSnapshot) throws {
        let data = document.data()
        let isDeleted = data["deletedAt"] != nil
        self.init(
            cardID: document.documentID,
            content: isDeleted ? nil : try Self.cardContent(from: data),
            cardNumber: data["cardNumber"] as? Int ?? 0,
            isPinned: data["isPinned"] as? Bool ?? false,
            creationSourceRaw: data["creationSource"] as? String ?? CardCreationSource.manual.rawValue,
            createdAt: Self.date(in: data, key: "createdAt"),
            editedAt: Self.date(in: data, key: "editedAt") ?? .distantPast,
            syncRevision: data["syncRevision"] as? Int,
            isDeleted: isDeleted
        )
    }

    private static func cardContent(from data: [String: Any]) throws -> DraftCardContent {
        guard let payload = data["payload"], JSONSerialization.isValidJSONObject(payload) else {
            throw CloudSyncDecodingError.invalidCardPayload
        }
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(DeckJSONCardDTO.self, from: payloadData).draftCardContent()
    }

    private static func date(in data: [String: Any], key: String) -> Date? {
        if let timestamp = data[key] as? Timestamp { return timestamp.dateValue() }
        return data[key] as? Date
    }
}

nonisolated struct CloudSyncRemoteDeckSnapshot: Sendable {
    let header: CloudSyncRemoteDeckHeader
    let cards: [CloudSyncRemoteCardSnapshot]
}

actor CloudSyncRemoteImportActor {
    private let container: ModelContainer
    private let outbox: CloudSyncOutbox
    private var activeContext: ModelContext

    init(container: ModelContainer, outbox: CloudSyncOutbox) {
        self.container = container
        self.outbox = outbox
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.activeContext = context
    }

    func applyRemoteDeck(
        _ header: CloudSyncRemoteDeckHeader,
        uid: String
    ) async throws -> CloudSyncRemoteImportResult {
        if try await outbox.containsDelete(ownerUID: uid, deckID: header.deckID) {
            return .noUploadNeeded
        }

        let cards = header.isDeleted ? [] : try await remoteCards(uid: uid, deckID: header.deckID)
        return try apply(CloudSyncRemoteDeckSnapshot(header: header, cards: cards), uid: uid)
    }

    func apply(
        _ snapshot: CloudSyncRemoteDeckSnapshot,
        uid: String
    ) throws -> CloudSyncRemoteImportResult {
        defer { flushContext() }

        let header = snapshot.header
        let localDeck = try activeContext.fetch(FetchDescriptor<DeckModel>()).first(where: {
            $0.ownerUID == uid && $0.cloudID == header.deckID
        })

        if header.isDeleted {
            guard let localDeck else { return .noUploadNeeded }
            if CloudSyncCoordinator.localEditIsMeaningfullyNewer(localDeck.editedAt, than: header.editedAt) {
                return .enqueueLocalUpsert(deckID: header.deckID)
            }
            activeContext.delete(localDeck)
            try activeContext.save()
            return .noUploadNeeded
        }

        let deck: DeckModel
        if let localDeck {
            if CloudSyncCoordinator.localEditIsMeaningfullyNewer(localDeck.editedAt, than: header.editedAt) {
                return .enqueueLocalUpsert(deckID: header.deckID)
            }
            deck = localDeck
        } else {
            deck = DeckModel(title: header.title, colorHex: header.colorHex)
            deck.ownerUID = uid
            deck.cloudID = header.deckID
            activeContext.insert(deck)
        }

        deck.title = header.title
        deck.colorHex = header.colorHex
        deck.createdAt = header.createdAt ?? deck.createdAt
        deck.editedAt = header.editedAt
        deck.lastOpenedAt = header.lastOpenedAt
        deck.lastAssignedCardNumber = header.lastAssignedCardNumber ?? deck.lastAssignedCardNumber
        deck.syncRevision = header.syncRevision ?? deck.syncRevision
        deck.isNotFullySynced = header.isNotFullySynced
        deck.lastSyncedAt = Date()

        var localCardsByCloudID = [String: CardModel](minimumCapacity: deck.cardCount)
        for card in deck.cards where card.ownerUID == uid {
            guard let cloudID = card.cloudID else { continue }
            localCardsByCloudID[cloudID] = card
        }

        var shouldUploadLocal = false
        var resolvedCardCount = deck.cards.count
        let now = Date()

        for remoteCard in snapshot.cards {
            let localCard = localCardsByCloudID[remoteCard.cardID]

            if remoteCard.isDeleted {
                if let localCard, CloudSyncCoordinator.localEditIsMeaningfullyNewer(localCard.editedAt, than: remoteCard.editedAt) {
                    shouldUploadLocal = true
                } else if let localCard {
                    activeContext.delete(localCard)
                    localCardsByCloudID[remoteCard.cardID] = nil
                    resolvedCardCount = max(0, resolvedCardCount - 1)
                }
                continue
            }

            guard let content = remoteCard.content else { continue }
            if let localCard {
                if CloudSyncCoordinator.localEditIsMeaningfullyNewer(localCard.editedAt, than: remoteCard.editedAt) {
                    shouldUploadLocal = true
                    continue
                }
                applyRemoteCard(localCard, remoteCard: remoteCard, content: content, now: now)
            } else {
                let card = CardModel(
                    content: content,
                    cardNumber: remoteCard.cardNumber,
                    isPinned: remoteCard.isPinned,
                    creationSource: CardCreationSource(rawValue: remoteCard.creationSourceRaw) ?? .manual
                )
                card.ownerUID = uid
                card.cloudID = remoteCard.cardID
                applyRemoteCard(card, remoteCard: remoteCard, content: content, now: now)
                card.deck = deck
                deck.cards.append(card)
                activeContext.insert(card)
                localCardsByCloudID[remoteCard.cardID] = card
                resolvedCardCount += 1
            }
        }

        deck.cardCount = resolvedCardCount
        try activeContext.save()
        return shouldUploadLocal ? .enqueueLocalUpsert(deckID: header.deckID) : .noUploadNeeded
    }

    private func remoteCards(uid: String, deckID: String) async throws -> [CloudSyncRemoteCardSnapshot] {
        let documents = try await Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("decks")
            .document(deckID)
            .collection("cards")
            .getDocuments()
            .documents
        return try documents.map(CloudSyncRemoteCardSnapshot.init(document:))
    }

    private func applyRemoteCard(
        _ card: CardModel,
        remoteCard: CloudSyncRemoteCardSnapshot,
        content: DraftCardContent,
        now: Date
    ) {
        card.cardContent = content
        card.cardNumber = remoteCard.cardNumber
        card.isPinned = remoteCard.isPinned
        card.creationSourceRaw = remoteCard.creationSourceRaw
        card.createdAt = remoteCard.createdAt ?? card.createdAt
        card.editedAt = remoteCard.editedAt
        card.syncRevision = remoteCard.syncRevision ?? card.syncRevision
        card.lastSyncedAt = now
    }

    private func flushContext() {
        let freshContext = ModelContext(container)
        freshContext.autosaveEnabled = false
        activeContext = freshContext
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
