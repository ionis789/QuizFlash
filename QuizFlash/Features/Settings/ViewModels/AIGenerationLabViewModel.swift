#if DEBUG
import CryptoKit
import Foundation
import ImageIO
import Observation
import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum AIGenerationLabSourceKind: String, Codable, Equatable, Sendable {
    case pdf
    case image
}

nonisolated struct AIGenerationLabSource: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: AIGenerationLabSourceKind
    let displayName: String
    let storedFilename: String
    let byteCount: Int64
    let sha256: String
    let pageCount: Int?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let addedAtEpochMilliseconds: Int64
}

nonisolated struct AIGenerationLabManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var sources: [AIGenerationLabSource] = []
    var targetCardCount = 30
    var options = AIGenerationOptions()
}

nonisolated struct AIGenerationLabImageImport: Sendable {
    let data: Data
    let displayName: String
    let filenameExtension: String
}

nonisolated enum AIGenerationLabStoreError: LocalizedError {
    case unsupportedManifest
    case invalidPDF
    case invalidImage
    case unreadablePhoto
    case missingStoredSource

    var errorDescription: String? {
        switch self {
        case .unsupportedManifest:
            return "The saved lab manifest is not supported by this build."
        case .invalidPDF:
            return "One of the selected files is not a readable PDF."
        case .invalidImage:
            return "One of the selected files is not a readable image."
        case .unreadablePhoto:
            return "One of the selected photos could not be read."
        case .missingStoredSource:
            return "A saved lab source is missing from storage."
        }
    }
}

/// Owns the reproducible on-disk corpus used by the AI generation lab.
actor AIGenerationLabCorpusStore {
    static let shared = AIGenerationLabCorpusStore()

    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let sourcesDirectoryURL: URL
    private let manifestURL: URL

    init(
        rootDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager

        if let rootDirectoryURL {
            self.rootDirectoryURL = rootDirectoryURL
        } else {
            guard let applicationSupportURL = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                preconditionFailure("Application Support is unavailable.")
            }
            self.rootDirectoryURL = applicationSupportURL
                .appendingPathComponent("AIGenerationLabCorpus", isDirectory: true)
        }

        sourcesDirectoryURL = self.rootDirectoryURL
            .appendingPathComponent("Sources", isDirectory: true)
        manifestURL = self.rootDirectoryURL.appendingPathComponent("manifest.json")
    }

    func loadManifest() throws -> AIGenerationLabManifest {
        try prepareDirectories()
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return AIGenerationLabManifest()
        }

        let data = try Data(contentsOf: manifestURL)
        let manifest = try decoder.decode(AIGenerationLabManifest.self, from: data)
        guard manifest.schemaVersion == AIGenerationLabManifest.currentSchemaVersion else {
            throw AIGenerationLabStoreError.unsupportedManifest
        }
        guard manifest.sources.allSatisfy({ source in
            fileManager.fileExists(
                atPath: sourcesDirectoryURL.appendingPathComponent(source.storedFilename).path
            )
        }) else {
            throw AIGenerationLabStoreError.missingStoredSource
        }
        return manifest
    }

    func saveManifest(_ manifest: AIGenerationLabManifest) throws {
        guard manifest.schemaVersion == AIGenerationLabManifest.currentSchemaVersion else {
            throw AIGenerationLabStoreError.unsupportedManifest
        }
        try prepareDirectories()
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: [.atomic, .completeFileProtection])
    }

    func importPDFs(
        from urls: [URL],
        appendingTo manifest: AIGenerationLabManifest
    ) throws -> AIGenerationLabManifest {
        try prepareDirectories()
        var importedSources: [AIGenerationLabSource] = []

        do {
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                guard let document = PDFDocument(data: data), document.pageCount > 0 else {
                    throw AIGenerationLabStoreError.invalidPDF
                }

                importedSources.append(
                    try persistSource(
                        data: data,
                        kind: .pdf,
                        displayName: url.deletingPathExtension().lastPathComponent,
                        filenameExtension: "pdf",
                        pageCount: document.pageCount,
                        pixelSize: nil
                    )
                )
            }

            var updatedManifest = manifest
            updatedManifest.sources.append(contentsOf: importedSources)
            try saveManifest(updatedManifest)
            return updatedManifest
        } catch {
            removeStoredFiles(for: importedSources)
            throw error
        }
    }

    func importImages(
        _ imports: [AIGenerationLabImageImport],
        appendingTo manifest: AIGenerationLabManifest
    ) throws -> AIGenerationLabManifest {
        try prepareDirectories()
        var importedSources: [AIGenerationLabSource] = []

        do {
            for imageImport in imports {
                guard let pixelSize = Self.imagePixelSize(from: imageImport.data) else {
                    throw AIGenerationLabStoreError.invalidImage
                }

                importedSources.append(
                    try persistSource(
                        data: imageImport.data,
                        kind: .image,
                        displayName: imageImport.displayName,
                        filenameExtension: Self.safeExtension(imageImport.filenameExtension),
                        pageCount: nil,
                        pixelSize: pixelSize
                    )
                )
            }

            var updatedManifest = manifest
            updatedManifest.sources.append(contentsOf: importedSources)
            try saveManifest(updatedManifest)
            return updatedManifest
        } catch {
            removeStoredFiles(for: importedSources)
            throw error
        }
    }

    func moveSource(
        id: UUID,
        by offset: Int,
        in manifest: AIGenerationLabManifest
    ) throws -> AIGenerationLabManifest {
        guard let sourceIndex = manifest.sources.firstIndex(where: { $0.id == id }) else {
            return manifest
        }

        let destinationIndex = sourceIndex + offset
        guard manifest.sources.indices.contains(destinationIndex) else {
            return manifest
        }

        var updatedManifest = manifest
        updatedManifest.sources.swapAt(sourceIndex, destinationIndex)
        try saveManifest(updatedManifest)
        return updatedManifest
    }

    func removeSource(
        id: UUID,
        from manifest: AIGenerationLabManifest
    ) throws -> AIGenerationLabManifest {
        guard let source = manifest.sources.first(where: { $0.id == id }) else {
            return manifest
        }

        var updatedManifest = manifest
        updatedManifest.sources.removeAll { $0.id == id }
        try saveManifest(updatedManifest)

        let storedURL = sourcesDirectoryURL.appendingPathComponent(source.storedFilename)
        try? fileManager.removeItem(at: storedURL)
        return updatedManifest
    }

    func storedFileURL(for source: AIGenerationLabSource) -> URL {
        sourcesDirectoryURL.appendingPathComponent(source.storedFilename)
    }

    private func persistSource(
        data: Data,
        kind: AIGenerationLabSourceKind,
        displayName: String,
        filenameExtension: String,
        pageCount: Int?,
        pixelSize: (width: Int, height: Int)?
    ) throws -> AIGenerationLabSource {
        let id = UUID()
        let storedFilename = id.uuidString + "." + filenameExtension
        let destinationURL = sourcesDirectoryURL.appendingPathComponent(storedFilename)
        try data.write(to: destinationURL, options: [.atomic, .completeFileProtection])

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDestinationURL = destinationURL
        try? mutableDestinationURL.setResourceValues(resourceValues)

        return AIGenerationLabSource(
            id: id,
            kind: kind,
            displayName: displayName.isEmpty ? storedFilename : displayName,
            storedFilename: storedFilename,
            byteCount: Int64(data.count),
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            pageCount: pageCount,
            pixelWidth: pixelSize?.width,
            pixelHeight: pixelSize?.height,
            addedAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        )
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(
            at: sourcesDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )

        var rootResourceValues = URLResourceValues()
        rootResourceValues.isExcludedFromBackup = true
        var mutableRootURL = rootDirectoryURL
        try? mutableRootURL.setResourceValues(rootResourceValues)
    }

    private func removeStoredFiles(for sources: [AIGenerationLabSource]) {
        for source in sources {
            let storedURL = sourcesDirectoryURL.appendingPathComponent(source.storedFilename)
            try? fileManager.removeItem(at: storedURL)
        }
    }

    private static func imagePixelSize(from data: Data) -> (width: Int, height: Int)? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0 else {
            return nil
        }
        return (width, height)
    }

    private static func safeExtension(_ value: String) -> String {
        let normalized = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return normalized.isEmpty ? "img" : normalized
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        JSONDecoder()
    }
}

@Observable
@MainActor
final class AIGenerationLabViewModel {
    private(set) var sources: [AIGenerationLabSource] = []
    private(set) var isWorking = false
    private(set) var hasLoaded = false
    var targetCardCount = 30 {
        didSet {
            let clampedValue = min(max(targetCardCount, 5), 100)
            if targetCardCount != clampedValue {
                targetCardCount = clampedValue
            }
            scheduleConfigurationPersistence()
        }
    }
    var options = AIGenerationOptions() {
        didSet {
            let normalizedInstructions = String(
                options.userInstructions.prefix(AIGenerationOptions.maximumUserInstructionsLength)
            )
            if options.userInstructions != normalizedInstructions {
                options.userInstructions = normalizedInstructions
            }
            scheduleConfigurationPersistence()
        }
    }
    var isShowingError = false
    var errorMessage = ""

    @ObservationIgnored private let store: AIGenerationLabCorpusStore
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var isApplyingManifest = false

    init(store: AIGenerationLabCorpusStore = .shared) {
        self.store = store
    }

    func load() async {
        guard !hasLoaded else { return }
        isWorking = true
        defer {
            isWorking = false
            hasLoaded = true
        }

        do {
            apply(try await store.loadManifest())
        } catch {
            present(error)
        }
    }

    func importPDFs(_ result: Result<[URL], Error>) async {
        guard !isWorking else { return }
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            await performMutation {
                try await store.importPDFs(from: urls, appendingTo: currentManifest)
            }
        case .failure(let error):
            present(error)
        }
    }

    func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !isWorking, !items.isEmpty else { return }
        isWorking = true
        persistenceTask?.cancel()
        defer { isWorking = false }

        do {
            var imports: [AIGenerationLabImageImport] = []
            let existingImageCount = sources.lazy.filter { $0.kind == .image }.count

            for (offset, item) in items.enumerated() {
                try Task.checkCancellation()
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw AIGenerationLabStoreError.unreadablePhoto
                }

                let contentType = item.supportedContentTypes.first(where: { $0.conforms(to: .image) })
                imports.append(
                    AIGenerationLabImageImport(
                        data: data,
                        displayName: String(
                            format: "IMG-%03d",
                            existingImageCount + offset + 1
                        ),
                        filenameExtension: contentType?.preferredFilenameExtension ?? "img"
                    )
                )
            }

            apply(try await store.importImages(imports, appendingTo: currentManifest))
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    func moveSource(id: UUID, by offset: Int) async {
        guard !isWorking else { return }
        await performMutation {
            try await store.moveSource(id: id, by: offset, in: currentManifest)
        }
    }

    func removeSource(id: UUID) async {
        guard !isWorking else { return }
        await performMutation {
            try await store.removeSource(id: id, from: currentManifest)
        }
    }

    func canMoveSource(id: UUID, by offset: Int) -> Bool {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return false }
        return sources.indices.contains(index + offset)
    }

    private var currentManifest: AIGenerationLabManifest {
        AIGenerationLabManifest(
            sources: sources,
            targetCardCount: targetCardCount,
            options: options
        )
    }

    private func performMutation(
        _ mutation: () async throws -> AIGenerationLabManifest
    ) async {
        isWorking = true
        persistenceTask?.cancel()
        defer { isWorking = false }

        do {
            apply(try await mutation())
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    private func apply(_ manifest: AIGenerationLabManifest) {
        isApplyingManifest = true
        defer { isApplyingManifest = false }
        sources = manifest.sources
        targetCardCount = manifest.targetCardCount
        options = manifest.options
    }

    private func scheduleConfigurationPersistence() {
        guard hasLoaded, !isApplyingManifest else { return }
        persistenceTask?.cancel()
        let manifest = currentManifest
        let store = store

        persistenceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                try await store.saveManifest(manifest)
            } catch is CancellationError {
                return
            } catch {
                self?.present(error)
            }
        }
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }
}
#endif
