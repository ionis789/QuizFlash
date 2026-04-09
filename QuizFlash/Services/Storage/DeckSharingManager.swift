//
//  DeckSharingManager.swift
//  QuizFlash
//

import Foundation
import SwiftData
import UniformTypeIdentifiers
import Combine
import Compression
import OSLog

// MARK: - Exportable Models (Codable versions for JSON)
///  Professional Export/Import system for sharing decks between users.
///  Uses .qflash file format (ZIP archive with metadata.json and /assets folder)

/// Exportable version of ZoneModel (already Codable)
typealias ExportableZone = ZoneModel

/// Exportable card structure
struct ExportableCard: Codable {
    var id: UUID
    var content: DraftCardContent
    var creationSource: CardCreationSource
    var conversionMetadata: CardConversionMetadata?
    var createdAt: Date
    var editedAt: Date

    // Asset references (UUIDs of images stored in /assets folder)
    var assetReferences: [UUID]

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case content
        case creationSource
        case conversionMetadata
        case frontZone
        case backZone
        case frontType
        case backType
        case createdAt
        case editedAt
        case assetReferences
    }

    init(
        id: UUID,
        content: DraftCardContent,
        creationSource: CardCreationSource,
        conversionMetadata: CardConversionMetadata? = nil,
        createdAt: Date,
        editedAt: Date,
        assetReferences: [UUID]
    ) {
        self.id = id
        self.content = content
        self.creationSource = creationSource
        self.conversionMetadata = conversionMetadata
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.assetReferences = assetReferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        creationSource = try container.decodeIfPresent(CardCreationSource.self, forKey: .creationSource) ?? .manual
        conversionMetadata = try container.decodeIfPresent(CardConversionMetadata.self, forKey: .conversionMetadata)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        editedAt = try container.decode(Date.self, forKey: .editedAt)
        assetReferences = try container.decodeIfPresent([UUID].self, forKey: .assetReferences) ?? []

        if let decodedContent = try container.decodeIfPresent(DraftCardContent.self, forKey: .content) {
            content = decodedContent
            return
        }

        let frontZone = try container.decodeIfPresent(ZoneModel.self, forKey: .frontZone) ?? .text()
        let backZone = try container.decodeIfPresent(ZoneModel.self, forKey: .backZone) ?? .text()
        let frontType = try container.decodeIfPresent(CardContentType.self, forKey: .frontType) ?? .text
        let backType = try container.decodeIfPresent(CardContentType.self, forKey: .backType) ?? .text

        content = .flashcard(
            FlashcardCardContent(
                frontZone: frontZone,
                backZone: backZone,
                frontType: frontType,
                backType: backType
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(content.kind, forKey: .kind)
        try container.encode(content, forKey: .content)
        try container.encode(creationSource, forKey: .creationSource)
        try container.encodeIfPresent(conversionMetadata, forKey: .conversionMetadata)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(editedAt, forKey: .editedAt)
        try container.encode(assetReferences, forKey: .assetReferences)

        if case .flashcard(let flashcardContent) = content {
            try container.encode(flashcardContent.frontZone, forKey: .frontZone)
            try container.encode(flashcardContent.backZone, forKey: .backZone)
            try container.encode(flashcardContent.frontType, forKey: .frontType)
            try container.encode(flashcardContent.backType, forKey: .backType)
        }
    }
}

/// Exportable deck structure
struct ExportableDeck: Codable {
    var id: UUID
    var title: String
    var colorHex: String
    var createdAt: Date
    var editedAt: Date
    var cards: [ExportableCard]

    // File format version for future compatibility
    var formatVersion: Int = 2
    var appVersion: String = "1.0"
}

// MARK: - Asset Reference

/// Tracks image data and its reference UUID
struct AssetReference: Identifiable {
    let id: UUID
    let data: Data
    let originalZoneID: UUID
}

// MARK: - Export/Import Errors

enum DeckSharingError: LocalizedError {
    case exportFailed(String)
    case importFailed(String)
    case invalidFormat
    case missingMetadata
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
            return "Invalid file format. Expected .qflash file."
        case .missingMetadata:
            return "File is missing metadata.json"
        case .corruptedData:
            return "File data is corrupted"
        case .versionMismatch(let version):
            return "Unsupported file version: \(version)"
        case .fileAccessDenied:
            return "Cannot access file. Please check permissions."
        }
    }
}

// MARK: - Deck Sharing Manager

/// Manages export and import of decks using the `.qflash` file format.
///
/// The format is a single JSON file with Base64-encoded image assets embedded
/// in `ZoneModel` values. This avoids ZIP-compression issues while keeping the
/// file self-contained and easy to share.
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

    private let fileExtension = "qflash"
    private let metadataFileName = "metadata.json"
    private let assetsFolder = "assets"
    private let logger = QuizFlashLog.make("DeckSharingManager")

    private init() { }

    // MARK: - Export

    /// Exports a deck to a `.qflash` file and returns its temporary URL.
    ///
    /// The returned URL points to a file inside `FileManager.temporaryDirectory`.
    /// Pass it directly to a `ShareLink` or `UIActivityViewController`.
    ///
    /// - Parameter deck: The `DeckModel` to export.
    /// - Returns: The URL of the generated `.qflash` file.
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

        // Process cards - keep images as Base64 in zones
        var exportableCards: [ExportableCard] = []

        let totalCards = deck.cardCount
        for (index, card) in deck.cards.enumerated() {
            progress = 0.1 + (0.5 * Double(index) / Double(max(totalCards, 1)))

            // Copy zones directly - imageData will be encoded as Base64 by JSONEncoder
            let exportableCard = ExportableCard(
                id: UUID(),
                content: card.cardContent,
                creationSource: card.creationSource,
                conversionMetadata: card.conversionMetadata,
                createdAt: card.createdAt,
                editedAt: card.editedAt,
                assetReferences: []
            )
            exportableCards.append(exportableCard)
        }

        progress = 0.6
        currentOperation = "Creating file..."

        // Create exportable deck
        let exportableDeck = ExportableDeck(
            id: UUID(),
            title: deck.title,
            colorHex: deck.colorHex,
            createdAt: deck.createdAt,
            editedAt: deck.editedAt,
            cards: exportableCards
        )

        // Encode to JSON (imageData becomes Base64 automatically)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys] // Remove prettyPrinted for smaller file
        encoder.dateEncodingStrategy = .iso8601
        let exportData = try encoder.encode(exportableDeck)

        progress = 0.8
        currentOperation = "Saving file..."

        // Save as .qflash file
        let sanitizedTitle = deck.title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let archiveName = "\(sanitizedTitle).\(fileExtension)"
        let archiveURL = FileManager.default.temporaryDirectory.appendingPathComponent(archiveName)

        // Remove existing file if any
        try? FileManager.default.removeItem(at: archiveURL)

        // Write JSON data directly
        try exportData.write(to: archiveURL)

        progress = 1.0
        currentOperation = "Export complete!"

        logger.debug(
            "Exported deck '\(deck.title, privacy: .public)' - \(exportData.count) bytes, \(exportableCards.count) cards"
        )

        return archiveURL
    }


    // MARK: - Import

    /// Imports a deck from a `.qflash` file URL into the given `ModelContext`.
    ///
    /// - Parameters:
    ///   - url: The file URL of the `.qflash` archive (may be security-scoped).
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

        // 1. Verify file extension
        guard url.pathExtension.lowercased() == fileExtension else {
            throw DeckSharingError.invalidFormat
        }

        // 2. Start accessing security-scoped resource if needed
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        progress = 0.2
        currentOperation = "Reading file..."

        // 3. Read JSON data directly from file
        let jsonData = try Data(contentsOf: url)
        logger.debug("Read \(jsonData.count) bytes from import file")

        progress = 0.4
        currentOperation = "Parsing data..."

        // 4. Decode JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exportedDeck = try decoder.decode(ExportableDeck.self, from: jsonData)

        logger.debug(
            "Decoded deck '\(exportedDeck.title, privacy: .public)' with \(exportedDeck.cards.count) cards"
        )

        // 5. Validate format version
        if exportedDeck.formatVersion > 2 {
            throw DeckSharingError.versionMismatch(exportedDeck.formatVersion)
        }

        progress = 0.6
        currentOperation = "Creating deck..."

        // 6. Create new DeckModel
        let newDeck = DeckModel(
            title: exportedDeck.title,
            colorHex: exportedDeck.colorHex
        )
        newDeck.createdAt = Date()
        newDeck.editedAt = Date()

        context.insert(newDeck)

        progress = 0.7
        currentOperation = "Importing cards..."

        // 7. Create cards – zones already contain imageData decoded from JSON
        let totalCards = exportedDeck.cards.count
        for (index, exportedCard) in exportedDeck.cards.enumerated() {
            progress = 0.7 + (0.25 * Double(index) / Double(max(totalCards, 1)))

            // Updated initializer to prevent `backingData` binding errors
            let newCard = CardModel(
                content: exportedCard.content,
                creationSource: exportedCard.creationSource,
                conversionMetadata: exportedCard.conversionMetadata
            )
            
            // Preserve original creation timestamps from the imported file
            newCard.createdAt = exportedCard.createdAt
            newCard.editedAt = exportedCard.editedAt
            newCard.deck = newDeck

            context.insert(newCard)
            newDeck.cards.append(newCard)
        }

        progress = 0.95
        currentOperation = "Saving..."

        // 8. Update denormalized card count
        newDeck.cardCount = newDeck.cards.count

        // 9. Save context
        try context.save()

        progress = 1.0
        currentOperation = "Import complete!"

        logger.debug(
            "Successfully imported deck '\(newDeck.title, privacy: .public)' with \(newDeck.cards.count) cards"
        )

        return newDeck
    }

    // MARK: - File Type Registration

    /// The UTType identifier for .qflash files
    static let qflashUTType = "com.quizflash.deck"

    /// Check if a URL is a valid .qflash file
    func isValidQFlashFile(_ url: URL) -> Bool {
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
/// temporary `.qflash` export files older than 24 hours.
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

                    // Check if it's a QuizFlash temp file
                    let filename = fileURL.lastPathComponent
                    if filename.contains("qflash") || fileURL.pathExtension == "zip" {
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

// MARK: - UTType Extension for .qflash files

extension UTType {
    static var qflash: UTType {
        UTType(exportedAs: "com.quizflash.deck", conformingTo: .data)
    }
}
