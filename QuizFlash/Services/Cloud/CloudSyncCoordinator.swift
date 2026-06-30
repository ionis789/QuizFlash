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
    @ObservationIgnored private var deckListener: ListenerRegistration?
    @ObservationIgnored private var folderListener: ListenerRegistration?
    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var processingTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var remoteImportActor: CloudSyncRemoteImportActor?
    @ObservationIgnored private var remoteImportTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRemoteDecks: [CloudSyncRemoteDeckHeader] = []
    @ObservationIgnored private var pendingRemoteFolders: [CloudSyncRemoteFolderHeader] = []

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
        deckListener = service.addDeckListener(uid: user.uid) { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                self?.handleRemoteSnapshot(snapshot, error: error)
            }
        }
        folderListener = service.addFolderListener(uid: user.uid) { [weak self] snapshot, error in
            Task { @MainActor [weak self] in
                self?.handleRemoteFolderSnapshot(snapshot, error: error)
            }
        }
        scheduleOutboxProcessing()
    }

    func stop() {
        deckListener?.remove()
        deckListener = nil
        folderListener?.remove()
        folderListener = nil
        processingTask?.cancel()
        processingTask = nil
        retryTask?.cancel()
        retryTask = nil
        remoteImportTask?.cancel()
        remoteImportTask = nil
        remoteImportActor = nil
        pendingRemoteDecks.removeAll()
        pendingRemoteFolders.removeAll()
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

    /// Assigns stable cloud IDs before a newly created folder is first saved.
    func assignCloudIdentityIfPossible(to folder: FolderModel) {
        guard let uid = currentUserID() else { return }
        assignCloudIdentity(to: folder, uid: uid)
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

    /// Queues a folder upsert after local persistence has completed successfully.
    func enqueueUpsert(for folder: FolderModel, context: ModelContext) {
        guard let uid = currentUserID() else { return }
        assignCloudIdentity(to: folder, uid: uid)

        do {
            try context.save()
        } catch {
            lastErrorMessage = error.localizedDescription
            return
        }

        guard let folderID = folder.cloudID else { return }
        Task { [weak self, outbox] in
            do {
                try await outbox.enqueue(ownerUID: uid, deckID: folderID, kind: .upsertFolder)
                self?.scheduleOutboxProcessing()
            } catch {
                self?.record(error)
            }
        }
    }

    /// Queues a cloud tombstone before the caller removes a local folder.
    func enqueueDelete(for folder: FolderModel) {
        guard let uid = currentUserID(), folder.ownerUID == uid, let folderID = folder.cloudID else { return }

        Task { [weak self, outbox] in
            do {
                try await outbox.enqueue(ownerUID: uid, deckID: folderID, kind: .deleteFolder)
                self?.scheduleOutboxProcessing()
            } catch {
                self?.record(error)
            }
        }
    }

    /// Queues a deck upsert by cloud ID from detached persistence paths.
    func enqueueUpsert(ownerUID: String, deckID: String) {
        guard ownerUID == currentUserID() else { return }

        Task { [weak self, outbox] in
            do {
                try await outbox.enqueue(ownerUID: ownerUID, deckID: deckID, kind: .upsertDeck)
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
                        let dailyStudyAggregates = try context.fetch(FetchDescriptor<HomeDailyStudyAggregate>())
                        let dailyDeckAggregates = try context.fetch(FetchDescriptor<HomeDailyDeckAggregate>())
                        let dailyCardAggregates = try context.fetch(FetchDescriptor<HomeDailyCardAggregate>())
                        try await service.upsertDeck(
                            deck,
                            uid: uid,
                            cards: deck.cards,
                            dailyStudyAggregates: dailyStudyAggregates,
                            dailyDeckAggregates: dailyDeckAggregates,
                            dailyCardAggregates: dailyCardAggregates
                        )
                        try context.save()
                    case .deleteDeck:
                        try await service.softDeleteDeck(deckID: operation.deckID, uid: uid)
                    case .upsertFolder:
                        guard let folder = try context.fetch(FetchDescriptor<FolderModel>()).first(where: {
                            $0.ownerUID == uid && $0.cloudID == operation.entityID
                        }) else {
                            try await outbox.remove(operation)
                            continue
                        }
                        try await service.upsertFolder(folder, uid: uid)
                        try context.save()
                    case .deleteFolder:
                        try await service.softDeleteFolder(folderID: operation.entityID, uid: uid)
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

    private func handleRemoteFolderSnapshot(_ snapshot: QuerySnapshot?, error: Error?) {
        if let error {
            lastErrorMessage = error.localizedDescription
            return
        }
        guard let snapshot else { return }

        let changedFolders = snapshot.documentChanges
            .filter { $0.type != .removed }
            .map { CloudSyncRemoteFolderHeader(document: $0.document) }
        guard !changedFolders.isEmpty else { return }

        pendingRemoteFolders.append(contentsOf: changedFolders)
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
        while !pendingRemoteFolders.isEmpty || !pendingRemoteDecks.isEmpty {
            guard !Task.isCancelled else { return }
            guard let uid = activeUID, let remoteImportActor else { return }

            if !pendingRemoteFolders.isEmpty {
                let header = pendingRemoteFolders.removeFirst()

                do {
                    try await remoteImportActor.applyRemoteFolder(header, uid: uid)
                    lastErrorMessage = nil
                } catch {
                    lastErrorMessage = error.localizedDescription
                }
                continue
            }

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
        if let folder = deck.folder {
            assignCloudIdentity(to: folder, uid: uid)
        }

        for card in deck.cards {
            card.ownerUID = uid
            if card.cloudID == nil { card.cloudID = UUID().uuidString }
            for event in card.reviewHistory {
                event.ownerUID = uid
                if event.cloudID == nil { event.cloudID = UUID().uuidString }
            }
        }
    }

    private func assignCloudIdentity(to folder: FolderModel, uid: String) {
        folder.ownerUID = uid
        if folder.cloudID == nil { folder.cloudID = UUID().uuidString }
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
    let folderID: String?
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
        folderID: String?,
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
        self.folderID = folderID
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
            folderID: data["folderID"] as? String,
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

nonisolated struct CloudSyncRemoteFolderHeader: Sendable {
    let folderID: String
    let title: String
    let colorHex: String
    let deckCount: Int
    let createdAt: Date?
    let editedAt: Date
    let syncRevision: Int?
    let isDeleted: Bool

    init(document: QueryDocumentSnapshot) {
        let data = document.data()
        folderID = document.documentID
        title = data["title"] as? String ?? ""
        colorHex = data["colorHex"] as? String ?? "#70707A"
        deckCount = data["deckCount"] as? Int ?? 0
        createdAt = Self.date(in: data, key: "createdAt")
        editedAt = Self.date(in: data, key: "editedAt") ?? .distantPast
        syncRevision = data["syncRevision"] as? Int
        isDeleted = data["deletedAt"] != nil
    }

    private static func date(in data: [String: Any], key: String) -> Date? {
        if let timestamp = data[key] as? Timestamp { return timestamp.dateValue() }
        return data[key] as? Date
    }
}

nonisolated struct CloudSyncRemoteReviewEventSnapshot: Sendable {
    let eventID: String
    let timestamp: Date
    let timeSpent: TimeInterval
    let difficultyRaw: Int
    let xpAwarded: Int

    init(document: QueryDocumentSnapshot) {
        let data = document.data()
        eventID = document.documentID
        timestamp = Self.date(in: data, key: "timestamp") ?? .distantPast
        timeSpent = data["timeSpent"] as? TimeInterval ?? 0
        difficultyRaw = data["difficultyRaw"] as? Int ?? ReviewDifficulty.good.rawValue
        xpAwarded = data["xpAwarded"] as? Int ?? 0
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
    let dueDate: Date?
    let easeFactor: Double?
    let interval: Int?
    let consecutiveCorrectAnswers: Int?
    let syncRevision: Int?
    let isDeleted: Bool
    let reviewEvents: [CloudSyncRemoteReviewEventSnapshot]

    init(
        cardID: String,
        content: DraftCardContent?,
        cardNumber: Int,
        isPinned: Bool,
        creationSourceRaw: String,
        createdAt: Date?,
        editedAt: Date,
        dueDate: Date?,
        easeFactor: Double?,
        interval: Int?,
        consecutiveCorrectAnswers: Int?,
        syncRevision: Int?,
        isDeleted: Bool,
        reviewEvents: [CloudSyncRemoteReviewEventSnapshot]
    ) {
        self.cardID = cardID
        self.content = content
        self.cardNumber = cardNumber
        self.isPinned = isPinned
        self.creationSourceRaw = creationSourceRaw
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.dueDate = dueDate
        self.easeFactor = easeFactor
        self.interval = interval
        self.consecutiveCorrectAnswers = consecutiveCorrectAnswers
        self.syncRevision = syncRevision
        self.isDeleted = isDeleted
        self.reviewEvents = reviewEvents
    }

    init(document: QueryDocumentSnapshot, reviewEvents: [CloudSyncRemoteReviewEventSnapshot] = []) throws {
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
            dueDate: Self.date(in: data, key: "dueDate"),
            easeFactor: data["easeFactor"] as? Double,
            interval: data["interval"] as? Int,
            consecutiveCorrectAnswers: data["consecutiveCorrectAnswers"] as? Int,
            syncRevision: data["syncRevision"] as? Int,
            isDeleted: isDeleted,
            reviewEvents: reviewEvents
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
    private var _context: ModelContext?

    private var activeContext: ModelContext {
        if let existing = _context { return existing }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        _context = context
        return context
    }

    init(container: ModelContainer, outbox: CloudSyncOutbox) {
        self.container = container
        self.outbox = outbox
    }

    func applyRemoteFolder(
        _ header: CloudSyncRemoteFolderHeader,
        uid: String
    ) async throws {
        if try await outbox.containsFolderDelete(ownerUID: uid, folderID: header.folderID) {
            return
        }

        defer { flushContext() }

        let localFolder = try activeContext.fetch(FetchDescriptor<FolderModel>()).first(where: {
            $0.ownerUID == uid && $0.cloudID == header.folderID
        })

        if header.isDeleted {
            guard let localFolder else { return }
            if CloudSyncCoordinator.localEditIsMeaningfullyNewer(localFolder.editedAt, than: header.editedAt) {
                try await outbox.enqueue(ownerUID: uid, deckID: header.folderID, kind: .upsertFolder)
                return
            }

            for deck in localFolder.decks {
                deck.folder = nil
                deck.editedAt = header.editedAt
            }
            activeContext.delete(localFolder)
            try activeContext.save()
            return
        }

        let folder: FolderModel
        if let localFolder {
            if CloudSyncCoordinator.localEditIsMeaningfullyNewer(localFolder.editedAt, than: header.editedAt) {
                try await outbox.enqueue(ownerUID: uid, deckID: header.folderID, kind: .upsertFolder)
                return
            }
            folder = localFolder
        } else {
            folder = FolderModel(title: header.title, colorHex: header.colorHex)
            folder.ownerUID = uid
            folder.cloudID = header.folderID
            activeContext.insert(folder)
        }

        folder.title = header.title
        folder.colorHex = header.colorHex
        folder.deckCount = header.deckCount
        folder.createdAt = header.createdAt ?? folder.createdAt
        folder.editedAt = header.editedAt
        folder.syncRevision = header.syncRevision ?? folder.syncRevision
        folder.lastSyncedAt = Date()
        try activeContext.save()
    }

    func applyRemoteDeck(
        _ header: CloudSyncRemoteDeckHeader,
        uid: String
    ) async throws -> CloudSyncRemoteImportResult {
        if try await outbox.containsDelete(ownerUID: uid, deckID: header.deckID) {
            return .noUploadNeeded
        }

        let cards = header.isDeleted ? [] : try await remoteCards(uid: uid, deckID: header.deckID)
        if !header.isDeleted {
            try await applyRemoteHomeAnalytics(uid: uid)
        }
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
        deck.folder = try resolveRemoteFolder(id: header.folderID, uid: uid)
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
        var snapshots: [CloudSyncRemoteCardSnapshot] = []
        snapshots.reserveCapacity(documents.count)

        for document in documents {
            let reviewDocuments = try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection("decks")
                .document(deckID)
                .collection("cards")
                .document(document.documentID)
                .collection("reviewEvents")
                .getDocuments()
                .documents
            let reviewEvents = reviewDocuments.map(CloudSyncRemoteReviewEventSnapshot.init(document:))
            snapshots.append(try CloudSyncRemoteCardSnapshot(document: document, reviewEvents: reviewEvents))
        }

        return snapshots
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
        card.dueDate = remoteCard.dueDate ?? card.dueDate
        card.easeFactor = remoteCard.easeFactor ?? card.easeFactor
        card.interval = remoteCard.interval ?? card.interval
        card.consecutiveCorrectAnswers = remoteCard.consecutiveCorrectAnswers ?? card.consecutiveCorrectAnswers
        card.syncRevision = remoteCard.syncRevision ?? card.syncRevision
        card.lastSyncedAt = now
        applyRemoteReviewEvents(remoteCard.reviewEvents, to: card, uid: card.ownerUID, now: now)
    }

    private func resolveRemoteFolder(id folderID: String?, uid: String) throws -> FolderModel? {
        guard let folderID else { return nil }

        if let folder = try activeContext.fetch(FetchDescriptor<FolderModel>()).first(where: {
            $0.ownerUID == uid && $0.cloudID == folderID
        }) {
            return folder
        }

        let placeholder = FolderModel(title: "Folder", colorHex: "#70707A")
        placeholder.ownerUID = uid
        placeholder.cloudID = folderID
        placeholder.editedAt = .distantPast
        activeContext.insert(placeholder)
        return placeholder
    }

    private func applyRemoteReviewEvents(
        _ remoteEvents: [CloudSyncRemoteReviewEventSnapshot],
        to card: CardModel,
        uid: String?,
        now: Date
    ) {
        var localEventsByCloudID = [String: ReviewEvent]()
        for event in card.reviewHistory {
            if let cloudID = event.cloudID {
                localEventsByCloudID[cloudID] = event
            }
        }

        for remoteEvent in remoteEvents where localEventsByCloudID[remoteEvent.eventID] == nil {
            let event = ReviewEvent(
                timeSpent: remoteEvent.timeSpent,
                difficulty: ReviewDifficulty(rawValue: remoteEvent.difficultyRaw) ?? .good,
                xpAwarded: remoteEvent.xpAwarded
            )
            event.timestamp = remoteEvent.timestamp
            event.cloudID = remoteEvent.eventID
            event.ownerUID = uid
            event.lastSyncedAt = now
            event.card = card
            card.reviewHistory.append(event)
            activeContext.insert(event)
        }
    }

    private func applyRemoteHomeAnalytics(uid: String) async throws {
        let firestore = Firestore.firestore()
        let userRef = firestore.collection("users").document(uid)
        let dailyStudy = try await userRef.collection("homeDailyStudy").getDocuments().documents
        let dailyDecks = try await userRef.collection("homeDailyDecks").getDocuments().documents
        let dailyCards = try await userRef.collection("homeDailyCards").getDocuments().documents

        try applyRemoteDailyStudy(dailyStudy)
        try applyRemoteDailyDecks(dailyDecks)
        try applyRemoteDailyCards(dailyCards)
    }

    private func applyRemoteDailyStudy(_ documents: [QueryDocumentSnapshot]) throws {
        for document in documents {
            let data = document.data()
            let dayKey = data["dayKey"] as? String ?? document.documentID
            let aggregate = try fetchOrCreateDailyStudy(dayKey: dayKey, data: data)
            aggregate.dayDate = date(in: data, key: "dayDate") ?? aggregate.dayDate
            aggregate.uniqueCardCount = data["uniqueCardCount"] as? Int ?? aggregate.uniqueCardCount
            aggregate.rawReviewCount = data["rawReviewCount"] as? Int ?? aggregate.rawReviewCount
            aggregate.landedCount = data["landedCount"] as? Int ?? aggregate.landedCount
            aggregate.retryCount = data["retryCount"] as? Int ?? aggregate.retryCount
            aggregate.xpEarned = data["xpEarned"] as? Int ?? aggregate.xpEarned
            aggregate.newCardsLearned = data["newCardsLearned"] as? Int ?? aggregate.newCardsLearned
            aggregate.dailyGoal = data["dailyGoal"] as? Int ?? aggregate.dailyGoal
        }
    }

    private func applyRemoteDailyDecks(_ documents: [QueryDocumentSnapshot]) throws {
        for document in documents {
            let data = document.data()
            let aggregateKey = data["aggregateKey"] as? String ?? document.documentID
            let aggregate = try fetchOrCreateDailyDeck(aggregateKey: aggregateKey, data: data)
            aggregate.dayKey = data["dayKey"] as? String ?? aggregate.dayKey
            aggregate.dayDate = date(in: data, key: "dayDate") ?? aggregate.dayDate
            aggregate.deckIdentifier = data["deckIdentifier"] as? String ?? aggregate.deckIdentifier
            aggregate.deckTitleSnapshot = data["deckTitleSnapshot"] as? String ?? aggregate.deckTitleSnapshot
            aggregate.deckColorHexSnapshot = data["deckColorHexSnapshot"] as? String ?? aggregate.deckColorHexSnapshot
            aggregate.uniqueCardCount = data["uniqueCardCount"] as? Int ?? aggregate.uniqueCardCount
            aggregate.landedCount = data["landedCount"] as? Int ?? aggregate.landedCount
            aggregate.retryCount = data["retryCount"] as? Int ?? aggregate.retryCount
        }
    }

    private func applyRemoteDailyCards(_ documents: [QueryDocumentSnapshot]) throws {
        for document in documents {
            let data = document.data()
            let aggregateKey = data["aggregateKey"] as? String ?? document.documentID
            let aggregate = try fetchOrCreateDailyCard(aggregateKey: aggregateKey, data: data)
            aggregate.dayKey = data["dayKey"] as? String ?? aggregate.dayKey
            aggregate.dayDate = date(in: data, key: "dayDate") ?? aggregate.dayDate
            aggregate.cardIdentifier = data["cardIdentifier"] as? String ?? aggregate.cardIdentifier
            aggregate.deckIdentifier = data["deckIdentifier"] as? String ?? aggregate.deckIdentifier
            aggregate.deckAggregateKey = data["deckAggregateKey"] as? String ?? aggregate.deckAggregateKey
            aggregate.deckTitleSnapshot = data["deckTitleSnapshot"] as? String ?? aggregate.deckTitleSnapshot
            aggregate.deckColorHexSnapshot = data["deckColorHexSnapshot"] as? String ?? aggregate.deckColorHexSnapshot
            aggregate.cardTitleSnapshot = data["cardTitleSnapshot"] as? String ?? aggregate.cardTitleSnapshot
            aggregate.finalDifficultyRaw = data["finalDifficultyRaw"] as? Int ?? aggregate.finalDifficultyRaw
            aggregate.repeatCount = data["repeatCount"] as? Int ?? aggregate.repeatCount
            aggregate.lastReviewedAt = date(in: data, key: "lastReviewedAt") ?? aggregate.lastReviewedAt
        }
    }

    private func fetchOrCreateDailyStudy(dayKey: String, data: [String: Any]) throws -> HomeDailyStudyAggregate {
        if let existing = try activeContext.fetch(FetchDescriptor<HomeDailyStudyAggregate>()).first(where: { $0.dayKey == dayKey }) {
            return existing
        }
        let aggregate = HomeDailyStudyAggregate(dayDate: date(in: data, key: "dayDate") ?? Date())
        aggregate.dayKey = dayKey
        activeContext.insert(aggregate)
        return aggregate
    }

    private func fetchOrCreateDailyDeck(aggregateKey: String, data: [String: Any]) throws -> HomeDailyDeckAggregate {
        if let existing = try activeContext.fetch(FetchDescriptor<HomeDailyDeckAggregate>()).first(where: { $0.aggregateKey == aggregateKey }) {
            return existing
        }
        let aggregate = HomeDailyDeckAggregate(
            dayDate: date(in: data, key: "dayDate") ?? Date(),
            deckIdentifier: data["deckIdentifier"] as? String ?? "unassigned",
            deck: nil,
            deckTitleSnapshot: data["deckTitleSnapshot"] as? String ?? "Untitled Deck",
            deckColorHexSnapshot: data["deckColorHexSnapshot"] as? String ?? "#70707A"
        )
        aggregate.aggregateKey = aggregateKey
        activeContext.insert(aggregate)
        return aggregate
    }

    private func fetchOrCreateDailyCard(aggregateKey: String, data: [String: Any]) throws -> HomeDailyCardAggregate {
        if let existing = try activeContext.fetch(FetchDescriptor<HomeDailyCardAggregate>()).first(where: { $0.aggregateKey == aggregateKey }) {
            return existing
        }
        let aggregate = HomeDailyCardAggregate(
            dayDate: date(in: data, key: "dayDate") ?? Date(),
            cardIdentifier: data["cardIdentifier"] as? String ?? "unassigned",
            deckIdentifier: data["deckIdentifier"] as? String ?? "unassigned",
            card: nil,
            deck: nil,
            deckTitleSnapshot: data["deckTitleSnapshot"] as? String ?? "Untitled Deck",
            deckColorHexSnapshot: data["deckColorHexSnapshot"] as? String ?? "#70707A",
            cardTitleSnapshot: data["cardTitleSnapshot"] as? String ?? "Untitled Card",
            finalDifficulty: ReviewDifficulty(rawValue: data["finalDifficultyRaw"] as? Int ?? ReviewDifficulty.good.rawValue) ?? .good,
            repeatCount: data["repeatCount"] as? Int ?? 0,
            lastReviewedAt: date(in: data, key: "lastReviewedAt") ?? Date()
        )
        aggregate.aggregateKey = aggregateKey
        activeContext.insert(aggregate)
        return aggregate
    }

    private func date(in data: [String: Any], key: String) -> Date? {
        if let timestamp = data[key] as? Timestamp { return timestamp.dateValue() }
        return data[key] as? Date
    }

    private func flushContext() {
        _context = nil
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
