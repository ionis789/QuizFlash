//
//  AIJobSessionStore.swift
//  QuizFlash
//
//  Disk persistence for resumable AI generation jobs.
//

import Foundation
import UIKit

// MARK: - Persisted AI Job Types

/// One persisted AI workspace job stored on disk.
nonisolated enum AIJobSession: Codable, Equatable, Sendable {
    case generation(AIPausedSession)

    private enum CodingKeys: String, CodingKey {
        case kind
        case generation
    }

    private enum Kind: String, Codable {
        case generation
    }

    var timestamp: Date {
        switch self {
        case .generation(let session):
            return session.timestamp
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .generation:
            self = .generation(try container.decode(AIPausedSession.self, forKey: .generation))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .generation(let session):
            try container.encode(Kind.generation, forKey: .kind)
            try container.encode(session, forKey: .generation)
        }
    }
}

// MARK: - Unified Store

/// Persists exactly one resumable AI job to Application Support.
actor AIJobSessionStore {
    static let shared = AIJobSessionStore()

    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let rootDirectoryURL: URL
    private let currentDate: @Sendable () -> Date

    private var applicationSupportDirectory: URL {
        let dir = rootDirectoryURL
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

    init(
        fileManager: FileManager = .default,
        rootDirectoryURL: URL? = nil,
        currentDate: @escaping @Sendable () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.currentDate = currentDate

        if let rootDirectoryURL {
            self.rootDirectoryURL = rootDirectoryURL
        } else {
            let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            self.rootDirectoryURL = urls[0].appendingPathComponent("QuizFlash", isDirectory: true)
        }
    }

    /// Persists the current AI workspace job atomically.
    func saveSession(_ session: AIJobSession) throws {
        try removeSessionFileIfNeeded()
        let data = try encoder.encode(session)
        try data.write(to: sessionFileURL, options: [.atomic, .completeFileProtection])
    }

    /// Loads the persisted job, transparently migrating legacy generation payloads.
    func loadSession() -> AIJobSession? {
        guard fileManager.fileExists(atPath: sessionFileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: sessionFileURL)
            let session: AIJobSession

            if let decoded = try? decoder.decode(AIJobSession.self, from: data) {
                session = decoded
            } else if let legacyGeneration = try? decoder.decode(AIPausedSession.self, from: data) {
                session = .generation(legacyGeneration)
            } else {
                throw NSError(
                    domain: "QuizFlashAIJobSessionStore",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The stored AI job session could not be decoded."]
                )
            }

            let age = currentDate().timeIntervalSince(session.timestamp)
            guard age < 86400 * 7 else {
                try? clearSession()
                return nil
            }

            return session
        } catch {
            try? clearSession()
            return nil
        }
    }

    /// Clears the active session file and any temporary assets linked to it.
    func clearSession() throws {
        try removeSessionFileIfNeeded()

        if fileManager.fileExists(atPath: imagesDirectoryURL.path) {
            try fileManager.removeItem(at: imagesDirectoryURL)
            try fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Saves temporary AI source photos to disk.
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

    /// Loads previously saved temporary AI source photos.
    func loadImagesFromDisk(at urls: [URL]) -> [UIImage] {
        var images: [UIImage] = []
        for url in urls {
            guard fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { continue }
            images.append(image)
        }
        return images
    }

    /// Creates a security-scoped bookmark for a PDF source.
    func createBookmark(for url: URL) throws -> Data {
        guard url.startAccessingSecurityScopedResource() else {
            throw NSError(
                domain: "QuizFlashAIJobSessionStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot access the selected document."]
            )
        }
        defer { url.stopAccessingSecurityScopedResource() }

        return try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolves a previously stored PDF bookmark.
    func resolveBookmark(data: Data) throws -> URL {
        var isStale = false
        return try URL(
            resolvingBookmarkData: data,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private func removeSessionFileIfNeeded() throws {
        if fileManager.fileExists(atPath: sessionFileURL.path) {
            try fileManager.removeItem(at: sessionFileURL)
        }
    }
}
