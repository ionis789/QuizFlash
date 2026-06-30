//
//  CloudSyncOutbox.swift
//  QuizFlash
//

import Foundation

// MARK: - Cloud Sync Operation

/// A durable local request to synchronize or soft-delete one cloud entity.
nonisolated struct CloudSyncOperation: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case upsertDeck
        case deleteDeck
        case upsertFolder
        case deleteFolder
    }

    let ownerUID: String
    let deckID: String
    let kind: Kind
    let requestedAt: Date

    var entityID: String { deckID }
}

// MARK: - Cloud Sync Outbox

/// Persists coalesced sync work so an interrupted upload resumes after relaunch.
actor CloudSyncOutbox {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL = CloudSyncOutbox.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func enqueue(ownerUID: String, deckID: String, kind: CloudSyncOperation.Kind) throws {
        var operations = try load()
        operations.removeAll { $0.ownerUID == ownerUID && $0.deckID == deckID }
        operations.append(
            CloudSyncOperation(
                ownerUID: ownerUID,
                deckID: deckID,
                kind: kind,
                requestedAt: Date()
            )
        )
        try persist(operations)
    }

    func operations(for ownerUID: String) throws -> [CloudSyncOperation] {
        try load()
            .filter { $0.ownerUID == ownerUID }
            .sorted { $0.requestedAt < $1.requestedAt }
    }

    func containsDelete(ownerUID: String, deckID: String) throws -> Bool {
        try load().contains {
            $0.ownerUID == ownerUID
                && $0.deckID == deckID
                && $0.kind == .deleteDeck
        }
    }

    func containsFolderDelete(ownerUID: String, folderID: String) throws -> Bool {
        try load().contains {
            $0.ownerUID == ownerUID
                && $0.deckID == folderID
                && $0.kind == .deleteFolder
        }
    }

    func remove(_ operation: CloudSyncOperation) throws {
        var operations = try load()
        operations.removeAll { $0 == operation }
        try persist(operations)
    }

    private func load() throws -> [CloudSyncOperation] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([CloudSyncOperation].self, from: Data(contentsOf: fileURL))
    }

    private func persist(_ operations: [CloudSyncOperation]) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(operations).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    nonisolated static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL.documentsDirectory

        return directory
            .appendingPathComponent("CloudSync", isDirectory: true)
            .appendingPathComponent("outbox.json", isDirectory: false)
    }
}
