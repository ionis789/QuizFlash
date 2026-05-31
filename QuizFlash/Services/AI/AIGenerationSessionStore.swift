//
//  AIGenerationSessionStore.swift
//  QuizFlash
//
//  Handles atomic disk persistence of paused AI generation sessions.
//

import Foundation
import UIKit
import SwiftData

/// Represents a paused AI generation session mapped to Codable primitives.
nonisolated struct AIPausedSession: Codable, Equatable {
    public let sessionID: UUID
    public let deckTitle: String
    public let folderID: String? // Stringified PersistentIdentifier if needed, or simply none since deck is drafted
    public let deckID: String?
    
    // Core Generation State
    public let targetCardCount: Int
    public let generatedCardCount: Int
    public let baseCardCount: Int
    
    // User Settings
    let options: AIGenerationOptions
    let remainingAllocations: [AISourceRangeAllocation]
    
    enum SourceMode: Codable, Equatable {
        case pdf(bookmarkData: Data, analysis: PDFAnalysisInfo?)
        case photos(fileURLs: [URL])
    }
    public let sourceMode: SourceMode
    
    // The current generated/drafted cards so we don't lose them if ViewModel recreates completely
    public let draftCards: [DraftCard]
    
    // The active provider ID used for this session
    public let providerProfileID: UUID?
    
    public let timestamp: Date
    
    init(
        sessionID: UUID,
        deckTitle: String,
        folderID: String?,
        deckID: String?,
        targetCardCount: Int,
        generatedCardCount: Int,
        baseCardCount: Int,
        options: AIGenerationOptions,
        remainingAllocations: [AISourceRangeAllocation],
        sourceMode: SourceMode,
        draftCards: [DraftCard],
        providerProfileID: UUID?,
        timestamp: Date = Date()
    ) {
        self.sessionID = sessionID
        self.deckTitle = deckTitle
        self.folderID = folderID
        self.deckID = deckID
        self.targetCardCount = targetCardCount
        self.generatedCardCount = generatedCardCount
        self.baseCardCount = baseCardCount
        self.options = options
        self.remainingAllocations = remainingAllocations
        self.sourceMode = sourceMode
        self.draftCards = draftCards
        self.providerProfileID = providerProfileID
        self.timestamp = timestamp
    }
}

// Ensure PDFAnalysisInfo conforms to Codable for the enum (since we control it in AIGenerationState.swift)
extension PDFAnalysisInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case quality, pageCount, extractedChars
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.quality = try container.decode(Double.self, forKey: .quality)
        self.pageCount = try container.decode(Int.self, forKey: .pageCount)
        self.extractedChars = try container.decode(Int.self, forKey: .extractedChars)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quality, forKey: .quality)
        try container.encode(pageCount, forKey: .pageCount)
        try container.encode(extractedChars, forKey: .extractedChars)
    }
}


/// Backward-compatible generation-specific facade over ``AIJobSessionStore``.
actor AIGenerationSessionStore {
    static let shared = AIGenerationSessionStore()

    private let jobStore: AIJobSessionStore

    init(
        fileManager: FileManager = .default,
        rootDirectoryURL: URL? = nil,
        currentDate: @escaping @Sendable () -> Date = Date.init
    ) {
        self.jobStore = AIJobSessionStore(
            fileManager: fileManager,
            rootDirectoryURL: rootDirectoryURL,
            currentDate: currentDate
        )
    }

    /// Persists the active session to disk securely.
    func saveSession(_ session: AIPausedSession) async throws {
        try await jobStore.saveSession(.generation(session))
    }

    /// Loads the persisted session from disk, if one exists and is valid.
    func loadSession() async -> AIPausedSession? {
        guard let session = await jobStore.loadSession() else { return nil }
        guard case .generation(let generationSession) = session else {
            return nil
        }
        return generationSession
    }

    /// Deletes the session state and any temporary files associated with it.
    func clearSession() async throws {
        try await jobStore.clearSession()
    }

    /// Helper to save array of `UIImage` into the application support directory and return their new URLs.
    func saveImagesToDisk(_ images: [UIImage]) async throws -> [URL] {
        try await jobStore.saveImagesToDisk(images)
    }

    /// Helper to load saved image URLs back into `UIImage` instances.
    func loadImagesFromDisk(at urls: [URL]) async -> [UIImage] {
        await jobStore.loadImagesFromDisk(at: urls)
    }

    /// Helper to create a Security-Scoped Bookmark for a PDF URL so it can be re-accessed later.
    func createBookmark(for url: URL) async throws -> Data {
        try await jobStore.createBookmark(for: url)
    }

    /// Helper to resolve a Security-Scoped Bookmark into a usable URL.
    func resolveBookmark(data: Data) async throws -> URL {
        try await jobStore.resolveBookmark(data: data)
    }
}
