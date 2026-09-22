//
//  AIJobSessionStore.swift
//  QuizFlash
//
//  Disk persistence for resumable AI generation jobs.
//

import Foundation
import UIKit
import CryptoKit

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

    private func accountDirectoryURL(for ownerUID: String) -> URL {
        let digest = SHA256.hash(data: Data(ownerUID.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let directory = applicationSupportDirectory
            .appendingPathComponent("ai_accounts", isDirectory: true)
            .appendingPathComponent(digest, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
        return directory
    }

    private func sessionFileURL(for ownerUID: String) -> URL {
        accountDirectoryURL(for: ownerUID).appendingPathComponent("paused_ai_session.json")
    }

    private func imagesDirectoryURL(for ownerUID: String) -> URL {
        let dir = accountDirectoryURL(for: ownerUID).appendingPathComponent("ai_session_images", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }

    private func pdfsDirectoryURL(for ownerUID: String) -> URL {
        let dir = accountDirectoryURL(for: ownerUID).appendingPathComponent("ai_session_pdfs", isDirectory: true)
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

    /// Removes the pre-account-scoping session and temporary assets. Their owner
    /// cannot be proven, so they must never be adopted by the next signed-in user.
    func removeLegacyUnscopedDataIfNeeded() throws {
        let legacyURLs = [
            applicationSupportDirectory.appendingPathComponent("paused_ai_session.json"),
            applicationSupportDirectory.appendingPathComponent("ai_session_images", isDirectory: true),
            applicationSupportDirectory.appendingPathComponent("ai_session_pdfs", isDirectory: true),
        ]
        for url in legacyURLs where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Persists the current AI workspace job atomically.
    func saveSession(_ session: AIJobSession, ownerUID: String) throws {
        try removeSessionFileIfNeeded(ownerUID: ownerUID)
        let data = try encoder.encode(session)
        try data.write(to: sessionFileURL(for: ownerUID), options: [.atomic, .completeFileProtection])
    }

    /// Loads the persisted job, transparently migrating legacy generation payloads.
    func loadSession(ownerUID: String) -> AIJobSession? {
        let sessionFileURL = sessionFileURL(for: ownerUID)
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
                try? clearSession(ownerUID: ownerUID)
                return nil
            }

            return session
        } catch {
            try? clearSession(ownerUID: ownerUID)
            return nil
        }
    }

    /// Clears the active session file and any temporary assets linked to it.
    func clearSession(ownerUID: String) throws {
        try removeSessionFileIfNeeded(ownerUID: ownerUID)

        let imagesDirectoryURL = imagesDirectoryURL(for: ownerUID)
        let pdfsDirectoryURL = pdfsDirectoryURL(for: ownerUID)

        if fileManager.fileExists(atPath: imagesDirectoryURL.path) {
            try fileManager.removeItem(at: imagesDirectoryURL)
            try fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }

        if fileManager.fileExists(atPath: pdfsDirectoryURL.path) {
            try fileManager.removeItem(at: pdfsDirectoryURL)
            try fileManager.createDirectory(at: pdfsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Saves temporary AI source photos to disk.
    func saveImagesToDisk(_ images: [UIImage], ownerUID: String) throws -> [URL] {
        let imagesDirectoryURL = imagesDirectoryURL(for: ownerUID)
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

    /// Copies an externally selected PDF into the app sandbox for stable access during generation.
    func importPDFToDisk(from sourceURL: URL, ownerUID: String) throws -> URL {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        PDFImportDebugStore.record(
            "importPDFToDisk start",
            details: [
                "didAccess": String(didAccess),
                "source": sourceURL.debugDescription
            ]
        )
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
            PDFImportDebugStore.record(
                "importPDFToDisk stopAccess",
                details: ["didAccess": String(didAccess)]
            )
        }

        let sourceExtension = sourceURL.pathExtension.isEmpty ? "pdf" : sourceURL.pathExtension
        let destinationURL = pdfsDirectoryURL(for: ownerUID)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(sourceExtension)

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            PDFImportDebugStore.record(
                "importPDFToDisk copyItem success",
                details: ["destination": destinationURL.path]
            )
        } catch {
            PDFImportDebugStore.record(
                "importPDFToDisk copyItem failed",
                details: ["error": error.localizedDescription]
            )
            let data = try Data(contentsOf: sourceURL)
            PDFImportDebugStore.record(
                "importPDFToDisk data fallback read",
                details: ["bytes": String(data.count)]
            )
            try data.write(to: destinationURL, options: [.atomic, .completeFileProtection])
            PDFImportDebugStore.record(
                "importPDFToDisk data fallback wrote",
                details: ["destination": destinationURL.path]
            )
        }

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDestinationURL = destinationURL
        try? mutableDestinationURL.setResourceValues(resourceValues)

        PDFImportDebugStore.record(
            "importPDFToDisk finished",
            details: [
                "exists": String(fileManager.fileExists(atPath: destinationURL.path)),
                "destination": destinationURL.path
            ]
        )

        return destinationURL
    }

    /// Creates a security-scoped bookmark for a PDF source.
    func createBookmark(for url: URL) throws -> Data {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

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

    private func removeSessionFileIfNeeded(ownerUID: String) throws {
        let sessionFileURL = sessionFileURL(for: ownerUID)
        if fileManager.fileExists(atPath: sessionFileURL.path) {
            try fileManager.removeItem(at: sessionFileURL)
        }
    }
}
