//
//  DeckSharingManager.swift
//  QuizFlash
//

import SwiftUI
import Foundation
import SwiftData
import UniformTypeIdentifiers
import Combine
import Compression

// MARK: - Exportable Models (Codable versions for JSON)
///  Professional Export/Import system for sharing decks between users.
///  Uses .qflash file format (ZIP archive with metadata.json and /assets folder)

/// Exportable version of ZoneModel (already Codable)
typealias ExportableZone = ZoneModel

/// Exportable card structure
struct ExportableCard: Codable {
    var id: UUID
    var frontZone: ZoneModel
    var backZone: ZoneModel
    var createdAt: Date
    var editedAt: Date

    // Asset references (UUIDs of images stored in /assets folder)
    var assetReferences: [UUID]
}

/// Exportable deck structure
struct ExportableDeck: Codable {
    var id: UUID
    var title: String
    var icon: String
    var colorHex: String
    var createdAt: Date
    var editedAt: Date
    var cards: [ExportableCard]

    // File format version for future compatibility
    var formatVersion: Int = 1
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

    private init() { }

    // MARK: - Export

    /// Export a deck to a .qflash file
    /// Returns the URL of the created file for sharing
    /// Format: Single JSON file with Base64-encoded images (no ZIP compression issues)
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

        let totalCards = deck.cards.count
        for (index, card) in deck.cards.enumerated() {
            progress = 0.1 + (0.5 * Double(index) / Double(max(totalCards, 1)))

            // Copy zones directly - imageData will be encoded as Base64 by JSONEncoder
            let frontZone = card.frontZone
            let backZone = card.backZone

            let exportableCard = ExportableCard(
                id: UUID(),
                frontZone: frontZone,
                backZone: backZone,
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
            icon: deck.icon,
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

        print("DEBUG: Exported deck '\(deck.title)' - \(exportData.count) bytes, \(exportableCards.count) cards")

        return archiveURL
    }

    /// Create a ZIP archive from a directory
    private func createZipArchive(from sourceDir: URL, to destinationURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var zipError: Error?

        coordinator.coordinate(readingItemAt: sourceDir, options: .forUploading, error: &coordinatorError) { zipURL in
            do {
                try FileManager.default.copyItem(at: zipURL, to: destinationURL)
            } catch {
                zipError = error
            }
        }

        if let error = coordinatorError {
            throw DeckSharingError.exportFailed(error.localizedDescription)
        }
        if let error = zipError {
            throw DeckSharingError.exportFailed(error.localizedDescription)
        }
    }

    /// Extract a ZIP archive to a directory using Foundation's built-in support
    private func extractZipArchive(from zipURL: URL, to destinationDir: URL) throws {
        let tempZipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("zip")

        defer {
            try? FileManager.default.removeItem(at: tempZipURL)
        }
        try FileManager.default.copyItem(at: zipURL, to: tempZipURL)
        try unzipFile(at: tempZipURL, to: destinationDir)
    }

    /// Simple ZIP extraction using miniz-style approach
    private func unzipFile(at sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let zipData = try Data(contentsOf: sourceURL)
        print("DEBUG: ZIP file size: \(zipData.count) bytes")

        guard let eocdIndex = findEndOfCentralDirectory(in: zipData) else {
            throw DeckSharingError.importFailed("Invalid ZIP format - no EOCD found")
        }
        print("DEBUG: EOCD found at index: \(eocdIndex)")

        let eocd = zipData[eocdIndex...]
        guard eocd.count >= 22 else {
            throw DeckSharingError.importFailed("Invalid ZIP format - EOCD too short")
        }

        let cdOffset = readUInt32(from: zipData, at: eocdIndex + 16)
        let cdCount = readUInt16(from: zipData, at: eocdIndex + 10)
        print("DEBUG: Central Directory at offset \(cdOffset), \(cdCount) entries")

        var extractedFiles: [String] = []

        // Parse Central Directory entries
        var offset = Int(cdOffset)
        for _ in 0..<cdCount {
            guard offset + 46 <= zipData.count else { break }
            let signature = readUInt32(from: zipData, at: offset)
            guard signature == 0x02014b50 else { break }

            let compressionMethod = readUInt16(from: zipData, at: offset + 10)
            let compressedSize = readUInt32(from: zipData, at: offset + 20)
            let uncompressedSize = readUInt32(from: zipData, at: offset + 24)
            let fileNameLength = Int(readUInt16(from: zipData, at: offset + 28))
            let extraLength = Int(readUInt16(from: zipData, at: offset + 30))
            let commentLength = Int(readUInt16(from: zipData, at: offset + 32))
            let localHeaderOffset = Int(readUInt32(from: zipData, at: offset + 42))
            let fileNameStart = offset + 46
            let fileNameEnd = fileNameStart + fileNameLength
            guard fileNameEnd <= zipData.count else { break }

            let fileNameData = zipData[fileNameStart..<fileNameEnd]
            guard let fileName = String(data: Data(fileNameData), encoding: .utf8) else {
                offset += 46 + fileNameLength + extraLength + commentLength
                continue
            }
            let localExtraLength = Int(readUInt16(from: zipData, at: localHeaderOffset + 28))
            let dataOffset = localHeaderOffset + 30 + fileNameLength + localExtraLength

            let destPath = destinationURL.appendingPathComponent(fileName)
            if fileName.hasSuffix("/") {
                try fileManager.createDirectory(at: destPath, withIntermediateDirectories: true)
                extractedFiles.append("\(fileName) (dir)")
            } else {
                try fileManager.createDirectory(at: destPath.deletingLastPathComponent(), withIntermediateDirectories: true)
                let dataEnd = dataOffset + Int(compressedSize)
                guard dataEnd <= zipData.count else { break }
                let compressedData = Data(zipData[dataOffset..<dataEnd])

                if compressionMethod == 0 {
                    try compressedData.write(to: destPath)
                    extractedFiles.append("\(fileName) (stored, \(compressedSize) bytes)")
                } else if compressionMethod == 8 {
                    if let decompressed = decompressDeflate(compressedData, expectedSize: Int(uncompressedSize)) {
                        try decompressed.write(to: destPath)
                        extractedFiles.append("\(fileName) (deflate, \(uncompressedSize) bytes)")
                    } else {
                        throw DeckSharingError.importFailed("Failed to decompress \(fileName)")
                    }
                } else {
                    throw DeckSharingError.importFailed("Unsupported compression method: \(compressionMethod)")
                }
            }

            offset += 46 + fileNameLength + extraLength + commentLength
        }

        print("DEBUG: Extracted \(extractedFiles.count) files:")
        for file in extractedFiles {
            print("  - \(file)")
        }
    }

    /// Find End of Central Directory signature in ZIP data
    private func findEndOfCentralDirectory(in data: Data) -> Int? {
        let signature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let minEOCDSize = 22
        for i in stride(from: data.count - minEOCDSize, through: max(0, data.count - 65557), by: -1) {
            if data[i] == signature[0] &&
                data[i + 1] == signature[1] &&
                data[i + 2] == signature[2] &&
                data[i + 3] == signature[3] {
                return i
            }
        }
        return nil
    }

    /// Read UInt16 little-endian from data
    private func readUInt16(from data: Data, at offset: Int) -> UInt16 {
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    /// Read UInt32 little-endian from data
    private func readUInt32(from data: Data, at offset: Int) -> UInt32 {
        return UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    /// Decompress deflate data using Compression framework
    private func decompressDeflate(_ data: Data, expectedSize: Int) -> Data? {
        let bufferSize = max(expectedSize * 2, 1024 * 1024)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destinationBuffer.deallocate() }

        var decompressedSize = data.withUnsafeBytes { sourcePtr -> Int in
            guard let baseAddress = sourcePtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                bufferSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        if decompressedSize > 0 {
            print("DEBUG: Decompressed with raw ZLIB: \(decompressedSize) bytes")
            return Data(bytes: destinationBuffer, count: decompressedSize)
        }
        var zlibData = Data([0x78, 0x9C])
        zlibData.append(data)

        decompressedSize = zlibData.withUnsafeBytes { sourcePtr -> Int in
            guard let baseAddress = sourcePtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                bufferSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                zlibData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        if decompressedSize > 0 {
            print("DEBUG: Decompressed with zlib header: \(decompressedSize) bytes")
            return Data(bytes: destinationBuffer, count: decompressedSize)
        }
        zlibData = Data([0x78, 0x01])
        zlibData.append(data)

        decompressedSize = zlibData.withUnsafeBytes { sourcePtr -> Int in
            guard let baseAddress = sourcePtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                bufferSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                zlibData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        if decompressedSize > 0 {
            print("DEBUG: Decompressed with zlib header (low): \(decompressedSize) bytes")
            return Data(bytes: destinationBuffer, count: decompressedSize)
        }
        decompressedSize = data.withUnsafeBytes { sourcePtr -> Int in
            guard let baseAddress = sourcePtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                destinationBuffer,
                bufferSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                data.count,
                nil,
                COMPRESSION_LZFSE
            )
        }

        if decompressedSize > 0 {
            print("DEBUG: Decompressed with LZFSE: \(decompressedSize) bytes")
            return Data(bytes: destinationBuffer, count: decompressedSize)
        }
        if data.count == expectedSize {
            print("DEBUG: Data already uncompressed")
            return data
        }

        print("DEBUG: All decompression methods failed for \(data.count) bytes, expected \(expectedSize)")
        return nil
    }

    /// Extract images from zone tree and save to assets folder
    private func extractAndReplaceAssets(
        in zone: inout ZoneModel,
        assetsDir: URL,
        assetMap: inout [Data: UUID],
        refs: inout [UUID]
    ) {
        // Process image data if present
        if let imageData = zone.imageData {
            let assetID: UUID

            // Check if we already have this image (deduplication)
            if let existingID = assetMap[imageData] {
                assetID = existingID
            } else {
                assetID = UUID()
                assetMap[imageData] = assetID

                // Save to assets folder
                let assetURL = assetsDir.appendingPathComponent("\(assetID.uuidString).bin")
                try? imageData.write(to: assetURL)
            }

            refs.append(assetID)

            // Replace imageData with nil (it's now in assets folder)
            // Store the asset ID in a way we can recover it during import
            // We'll use a placeholder in the zone's text field temporarily
            zone.imageData = nil
            zone.text = "[[ASSET:\(assetID.uuidString)]]"
        }

        // Process children recursively
        if var children = zone.children {
            for i in children.indices {
                extractAndReplaceAssets(in: &children[i], assetsDir: assetsDir, assetMap: &assetMap, refs: &refs)
            }
            zone.children = children
        }
    }

    // MARK: - Import

    /// Import a deck from a .qflash file URL
    /// Format: Single JSON file with Base64-encoded images
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
        print("DEBUG: Read \(jsonData.count) bytes from file")

        progress = 0.4
        currentOperation = "Parsing data..."

        // 4. Decode JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exportedDeck = try decoder.decode(ExportableDeck.self, from: jsonData)

        print("DEBUG: Decoded deck '\(exportedDeck.title)' with \(exportedDeck.cards.count) cards")

        // 5. Validate format version
        if exportedDeck.formatVersion > 1 {
            throw DeckSharingError.versionMismatch(exportedDeck.formatVersion)
        }

        progress = 0.6
        currentOperation = "Creating deck..."

        // 6. Create new DeckModel
        let newDeck = DeckModel(
            title: exportedDeck.title,
            icon: exportedDeck.icon,
            colorHex: exportedDeck.colorHex
        )
        newDeck.createdAt = Date()
        newDeck.editedAt = Date()

        context.insert(newDeck)

        progress = 0.7
        currentOperation = "Importing cards..."

        // 7. Create cards - zones already have imageData from JSON decoding
        let totalCards = exportedDeck.cards.count
        for (index, exportedCard) in exportedDeck.cards.enumerated() {
            progress = 0.7 + (0.25 * Double(index) / Double(max(totalCards, 1)))

            // NOU: Inițializatorul actualizat care previne eroarea de `backingData`
            let newCard = CardModel(
                frontZone: exportedCard.frontZone,
                backZone: exportedCard.backZone
            )
            
            // Păstrăm datele de creație originale din import!
            newCard.createdAt = exportedCard.createdAt
            newCard.editedAt = exportedCard.editedAt
            newCard.deck = newDeck

            context.insert(newCard)
            newDeck.cards.append(newCard)
        }

        progress = 0.95
        currentOperation = "Saving..."

        // 8. Save context
        try context.save()

        progress = 1.0
        currentOperation = "Import complete!"

        print("DEBUG: Successfully imported deck '\(newDeck.title)' with \(newDeck.cards.count) cards")

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

        // Calculate metadata size (title, icon, dates, etc.)
        let metadataSize: Int64 = Int64(deck.title.utf8.count + deck.icon.utf8.count + deck.colorHex.utf8.count + 100)
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
            cardCount: deck.cards.count,
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

@MainActor
final class GarbageCollector: ObservableObject {
    static let shared = GarbageCollector()

    @Published var isRunning = false
    @Published var lastCleanupDate: Date?
    @Published var bytesFreed: Int64 = 0

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
            print("Cleanup error: \(error)")
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
