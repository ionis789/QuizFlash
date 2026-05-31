//
//  DeckSharingManager.swift
//  QuizFlash
//

import Foundation
import SwiftData
import Combine
import OSLog

// MARK: - Export/Import Errors

enum DeckSharingError: LocalizedError {
    case exportFailed(String)
    case importFailed(String)
    case invalidFormat
    case corruptedData
    case versionMismatch(Int)
    case fileAccessDenied

    var errorDescription: String? {
        switch self {
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        case .invalidFormat:
            return "Invalid file format. Expected a QuizFlash JSON deck file."
        case .corruptedData:
            return "File data is corrupted"
        case .versionMismatch(let version):
            return "Unsupported deck JSON schema version: \(version)"
        case .fileAccessDenied:
            return "Cannot access file. Please check permissions."
        }
    }
}

// MARK: - Deck Sharing Manager

/// Manages export and import of decks using the canonical QuizFlash JSON format.
///
/// The format is a single `.json` document with Base64-encoded media embedded in
/// zone values. SwiftData remains the local runtime store.
///
/// All public methods are `async` and run on the `MainActor` so that `@Published`
/// progress properties are always mutated on the correct thread.
@MainActor
final class DeckSharingManager: ObservableObject {
    static let shared = DeckSharingManager()

    @Published var isExporting = false
    @Published var isImporting = false
    @Published var progress: Double = 0
    @Published var currentOperation: String = ""

    private let fileExtension = "json"
    private let logger = QuizFlashLog.make("DeckSharingManager")

    private init() { }

    // MARK: - Export

    /// Exports a deck to a `.json` file and returns its temporary URL.
    ///
    /// The returned URL points to a file inside `FileManager.temporaryDirectory`.
    /// Pass it directly to a `ShareLink` or `UIActivityViewController`.
    ///
    /// - Parameter deck: The `DeckModel` to export.
    /// - Returns: The URL of the generated `.json` file.
    /// - Throws: `DeckSharingError.exportFailed` if encoding or writing fails.
    func exportDeck(_ deck: DeckModel) async throws -> URL {
        isExporting = true
        progress = 0
        currentOperation = "Preparing export..."

        defer {
            isExporting = false
            progress = 1.0
            currentOperation = ""
        }

        progress = 0.1
        currentOperation = "Processing cards..."

        let sortedCards = deck.cards.sorted {
            if $0.cardNumber == $1.cardNumber {
                return $0.createdAt < $1.createdAt
            }
            return $0.cardNumber < $1.cardNumber
        }

        progress = 0.6
        currentOperation = "Creating file..."

        let exportDocument = DeckJSONDocument.from(deck: deck, cards: sortedCards)

        let exportData: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            exportData = try encoder.encode(exportDocument)
        } catch {
            logger.error("Failed to encode deck export payload: \(error.localizedDescription, privacy: .public)")
            throw DeckSharingError.exportFailed("The deck couldn't be prepared for export right now.")
        }

        progress = 0.8
        currentOperation = "Saving file..."

        let sanitizedTitle = deck.title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let fileName = "\(sanitizedTitle).\(fileExtension)"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try? FileManager.default.removeItem(at: fileURL)
            try exportData.write(to: fileURL)
        } catch {
            logger.error("Failed to write deck export file: \(error.localizedDescription, privacy: .public)")
            throw DeckSharingError.exportFailed("The deck file couldn't be created right now.")
        }

        progress = 1.0
        currentOperation = "Export complete!"

        logger.debug(
            "Exported deck '\(deck.title, privacy: .public)' - \(exportData.count) bytes, \(sortedCards.count) cards"
        )

        return fileURL
    }


    // MARK: - Import

    /// Imports a deck from a `.json` file URL into the given `ModelContext`.
    ///
    /// - Parameters:
    ///   - url: The file URL of the deck JSON document (may be security-scoped).
    ///   - context: The `ModelContext` in which the imported `DeckModel` will be saved.
    /// - Returns: The newly created and persisted `DeckModel`.
    /// - Throws: `DeckSharingError` if the file cannot be read, decoded, or saved.
    func importDeck(from url: URL, into context: ModelContext) async throws -> DeckModel {
        isImporting = true
        progress = 0
        currentOperation = "Opening file..."

        defer {
            isImporting = false
            progress = 1.0
            currentOperation = ""
        }

        guard url.pathExtension.lowercased() == fileExtension else {
            throw DeckSharingError.invalidFormat
        }

        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        progress = 0.2
        currentOperation = "Reading file..."

        let jsonData = try Data(contentsOf: url)
        logger.debug("Read \(jsonData.count) bytes from import file")

        progress = 0.4
        currentOperation = "Parsing data..."

        let document: DeckJSONDocument
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            document = try decoder.decode(DeckJSONDocument.self, from: jsonData)
        } catch {
            logger.error("Failed to decode deck JSON: \(error.localizedDescription, privacy: .public)")
            throw DeckSharingError.corruptedData
        }

        logger.debug(
            "Decoded deck '\(document.deck.title, privacy: .public)' with \(document.cards.count) cards"
        )

        guard document.schemaVersion == DeckJSONDocument.supportedSchemaVersion else {
            throw DeckSharingError.versionMismatch(document.schemaVersion)
        }

        progress = 0.6
        currentOperation = "Creating deck..."

        let newDeck = DeckModel(
            title: document.deck.title,
            colorHex: document.deck.colorHex
        )
        newDeck.createdAt = document.deck.createdAt
        newDeck.editedAt = document.deck.editedAt

        context.insert(newDeck)

        progress = 0.7
        currentOperation = "Importing cards..."

        let totalCards = document.cards.count
        for (index, cardRecord) in document.cards.enumerated() {
            progress = 0.7 + (0.25 * Double(index) / Double(max(totalCards, 1)))

            let content: DraftCardContent
            do {
                content = try cardRecord.card.draftCardContent()
            } catch {
                logger.error("Invalid card JSON payload: \(error.localizedDescription, privacy: .public)")
                throw DeckSharingError.corruptedData
            }

            let newCard = CardModel(
                content: content,
                cardNumber: index + 1,
                creationSource: cardRecord.creationSource
            )
            newCard.createdAt = cardRecord.createdAt
            newCard.editedAt = cardRecord.editedAt
            newCard.deck = newDeck

            context.insert(newCard)
            newDeck.cards.append(newCard)
        }

        progress = 0.95
        currentOperation = "Saving..."

        newDeck.cardCount = totalCards
        newDeck.lastAssignedCardNumber = totalCards

        do {
            try context.save()
        } catch {
            logger.error("Failed to persist imported deck: \(error.localizedDescription, privacy: .public)")
            throw DeckSharingError.importFailed("The imported deck couldn't be saved right now.")
        }

        progress = 1.0
        currentOperation = "Import complete!"

        logger.debug(
            "Successfully imported deck '\(newDeck.title, privacy: .public)' with \(totalCards) cards"
        )

        return newDeck
    }

    // MARK: - File Type Registration

    /// Check if a URL is a valid QuizFlash JSON deck file.
    func isValidDeckJSONFile(_ url: URL) -> Bool {
        return url.pathExtension.lowercased() == fileExtension
    }
}

// MARK: - Storage Manager

/// Calculates and tracks the on-device storage footprint of all decks.
///
/// Runs storage calculations asynchronously so the UI is never blocked.
@MainActor
final class StorageManager: ObservableObject {
    static let shared = StorageManager()

    @Published var totalStorageUsed: Int64 = 0
    @Published var deckStorageInfo: [UUID: DeckStorageInfo] = [:]
    @Published var isCalculating = false

    private init() { }

    /// Storage info for a single deck
    struct DeckStorageInfo: Identifiable {
        let id: UUID
        let deckTitle: String
        let totalBytes: Int64
        let cardCount: Int
        let imageCount: Int

        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        }
    }

    /// Calculate storage used by all decks
    func calculateStorage(for decks: [DeckModel]) async {
        isCalculating = true
        defer { isCalculating = false }

        var total: Int64 = 0
        var info: [UUID: DeckStorageInfo] = [:]

        for deck in decks {
            let deckInfo = await calculateDeckStorage(deck)
            info[deckInfo.id] = deckInfo
            total += deckInfo.totalBytes
        }

        deckStorageInfo = info
        totalStorageUsed = total
    }

    /// Calculate storage for a single deck
    func calculateDeckStorage(_ deck: DeckModel) async -> DeckStorageInfo {
        var totalBytes: Int64 = 0
        var imageCount = 0

        // Calculate metadata size (title, color, dates, etc.)
        let metadataSize: Int64 = Int64(deck.title.utf8.count + deck.colorHex.utf8.count + 100)
        totalBytes += metadataSize

        // Calculate each card's storage
        for card in deck.cards {
            // Front zone
            let frontZone = card.frontZone
            let (frontBytes, frontImages) = calculateZoneStorage(frontZone)
            totalBytes += frontBytes
            imageCount += frontImages

            // Back zone
            let backZone = card.backZone
            let (backBytes, backImages) = calculateZoneStorage(backZone)
            totalBytes += backBytes
            imageCount += backImages
        }

        return DeckStorageInfo(
            id: UUID(), // Use deck's persistent ID if available
            deckTitle: deck.title,
            totalBytes: totalBytes,
            cardCount: deck.cardCount,
            imageCount: imageCount
        )
    }

    /// Calculate storage for a zone tree
    private func calculateZoneStorage(_ zone: ZoneModel) -> (bytes: Int64, images: Int) {
        var totalBytes: Int64 = 0
        var imageCount = 0

        // Text content
        totalBytes += Int64(zone.text.utf8.count)

        // Image/Sketch data
        if let imageData = zone.imageData {
            totalBytes += Int64(imageData.count)
            imageCount += 1
        }

        // Metadata (formatting, etc.)
        totalBytes += 50 // Approximate overhead per zone

        // Children
        if let children = zone.children {
            for child in children {
                let (childBytes, childImages) = calculateZoneStorage(child)
                totalBytes += childBytes
                imageCount += childImages
            }
        }

        return (totalBytes, imageCount)
    }

    /// Format bytes to human-readable string
    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Garbage Collector

/// Cleans up orphaned image data and expired temporary files to reclaim storage.
///
/// Call `cleanupDeckData(_:context:)` before deleting a deck, and
/// `runFullCleanup(context:)` periodically (e.g. on app launch) to purge
/// temporary JSON export files older than 24 hours.
@MainActor
final class GarbageCollector: ObservableObject {
    static let shared = GarbageCollector()

    @Published var isRunning = false
    @Published var lastCleanupDate: Date?
    @Published var bytesFreed: Int64 = 0
    private let logger = QuizFlashLog.make("GarbageCollector")

    private init() { }

    /// Clean up orphaned data when a deck is deleted
    /// Call this BEFORE deleting the deck from SwiftData
    func cleanupDeckData(_ deck: DeckModel, context: ModelContext) async {
        isRunning = true
        defer { isRunning = false }

        var freedBytes: Int64 = 0

        
        for card in deck.cards {
            
            freedBytes += clearZoneImages(card.frontZone)

            freedBytes += clearZoneImages(card.backZone)
        }

        bytesFreed = freedBytes
        lastCleanupDate = Date()

        // 2. The actual deletion happens in SwiftData with cascade delete rule
        // The deck's cards will be deleted automatically
    }

    /// Recursively calculate bytes in zone images (for tracking)
    private func clearZoneImages(_ zone: ZoneModel) -> Int64 {
        var freedBytes: Int64 = 0

        if let imageData = zone.imageData {
            freedBytes += Int64(imageData.count)
        }

        if let children = zone.children {
            for child in children {
                freedBytes += clearZoneImages(child)
            }
        }

        return freedBytes
    }

    /// Run a full cleanup to find and remove orphaned data
    /// This should be called periodically or on app launch
    func runFullCleanup(context: ModelContext) async {
        isRunning = true
        defer { isRunning = false }

        // In SwiftData, orphaned data is handled by the cascade delete rule
        // This method is mainly for clearing temporary files

        let tempDir = FileManager.default.temporaryDirectory

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
            )

            var freedBytes: Int64 = 0
            let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago

            for fileURL in contents {
                // Only clean up old temporary files
                if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                    let creationDate = attributes[.creationDate] as? Date,
                    creationDate < cutoffDate {

                    if fileURL.pathExtension == "json" {
                        if let size = attributes[.size] as? Int64 {
                            freedBytes += size
                        }
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }
            }

            bytesFreed += freedBytes
            lastCleanupDate = Date()

        } catch {
            logger.error("Cleanup error: \(String(describing: error), privacy: .public)")
        }
    }

    /// Delete a single deck with full cleanup
    func deleteDeck(_ deck: DeckModel, context: ModelContext) async throws {
        // Track storage before deletion
        await cleanupDeckData(deck, context: context)

        // Delete from SwiftData (cascade will handle cards)
        context.delete(deck)

        // Save changes
        try context.save()

        // Clear image cache
        // Note: Make sure ImageCache exists in your project
        // ImageCache.shared.clearCache() // Re-enable this if ImageCache is available
    }
}
