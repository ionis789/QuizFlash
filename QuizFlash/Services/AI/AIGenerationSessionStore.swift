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
struct AIPausedSession: Codable, Equatable {
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


/// Persists `AIPausedSession` to Application Support.
actor AIGenerationSessionStore {
    static let shared = AIGenerationSessionStore()
    
    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    
    private var applicationSupportDirectory: URL {
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("QuizFlash", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }
    
    private var sessionFileURL: URL {
        applicationSupportDirectory.appendingPathComponent("paused_ai_session.json")
    }
    
    private var imagesDirectoryURL: URL {
        let dir = applicationSupportDirectory.appendingPathComponent("ai_session_images", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }
    
    private init() {
        // Private initialization for singleton
    }
    
    /// Persists the active session to disk securely.
    func saveSession(_ session: AIPausedSession) throws {
        try clearSession() // Clean up any old files/images first
        
        let data = try encoder.encode(session)
        
        // Write atomically with file protection to keep memory/storage clean 
        try data.write(to: sessionFileURL, options: [.atomic, .completeFileProtection])
    }
    
    /// Loads the persisted session from disk, if one exists and is valid.
    func loadSession() -> AIPausedSession? {
        guard fileManager.fileExists(atPath: sessionFileURL.path) else { return nil }
        
        do {
            let data = try Foundation.Data(contentsOf: sessionFileURL)
            let session = try decoder.decode(AIPausedSession.self, from: data)
            
            // Validate the session hasn't expired completely (e.g. older than 24 hours, optional but good practice)
            let age = Date().timeIntervalSince(session.timestamp)
            guard age < 86400 * 7 else { // 7 days max
                try? clearSession()
                return nil
            }
            
            return session
        } catch {
            print("Failed to load paused AI session: \(error)")
            try? clearSession()
            return nil
        }
    }
    
    /// Deletes the session state and any temporary files associated with it.
    func clearSession() throws {
        if fileManager.fileExists(atPath: sessionFileURL.path) {
            try fileManager.removeItem(at: sessionFileURL)
        }
        
        if fileManager.fileExists(atPath: imagesDirectoryURL.path) {
            try fileManager.removeItem(at: imagesDirectoryURL)
            try fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    /// Helper to save array of `UIImage` into the application support directory and return their new URLs.
    func saveImagesToDisk(_ images: [UIImage]) throws -> [URL] {
        var fileURLs: [URL] = []
        for (index, image) in images.enumerated() {
            guard let data = image.jpegData(compressionQuality: 0.8) else { continue }
            let url = imagesDirectoryURL.appendingPathComponent("image_\(index).jpg")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            fileURLs.append(url)
        }
        return fileURLs
    }
    
    /// Helper to convert saved image URLs back into `UIImage` instances.
    func loadImagesFromDisk(at urls: [URL]) -> [UIImage] {
        var images: [UIImage] = []
        for url in urls {
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Foundation.Data(contentsOf: url),
                  let image = UIImage(data: data) else { continue }
            images.append(image)
        }
        return images
    }
    
    /// Helper to create a Security-Scoped Bookmark for a PDF URL so it can be re-accessed later.
    func createBookmark(for url: URL) throws -> Data {
        guard url.startAccessingSecurityScopedResource() else {
            throw NSError(domain: "QuizFlashSessionStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access URL to create bookmark."])
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        return bookmarkData
    }
    
    /// Helper to resolve a Security-Scoped Bookmark into a usable URL.
    func resolveBookmark(data: Data) throws -> URL {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale)
        if isStale {
            // Re-bookmark if stale (best effort)
        }
        return url
    }
}
