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
    case photos
}

nonisolated struct AIGenerationLabSource: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: AIGenerationLabSourceKind
    let displayName: String
    let storedFilenames: [String]
    let byteCount: Int64
    let sha256: String
    let pageCount: Int?
    let imageCount: Int?
    let addedAtEpochMilliseconds: Int64
}

nonisolated struct AIGenerationLabManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

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
    private let reportsDirectoryURL: URL
    private let manifestURL: URL
    private let latestReportURL: URL

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
        reportsDirectoryURL = self.rootDirectoryURL
            .appendingPathComponent("Reports", isDirectory: true)
        manifestURL = self.rootDirectoryURL.appendingPathComponent("manifest.json")
        latestReportURL = reportsDirectoryURL.appendingPathComponent("latest.json")
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
            !source.storedFilenames.isEmpty && source.storedFilenames.allSatisfy { filename in
                fileManager.fileExists(
                    atPath: sourcesDirectoryURL.appendingPathComponent(filename).path
                )
            }
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
                    try persistPDFSource(
                        data: data,
                        displayName: url.deletingPathExtension().lastPathComponent,
                        pageCount: document.pageCount
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
            let photoSet = try persistPhotoSet(imports)
            importedSources.append(photoSet)
            var updatedManifest = manifest
            updatedManifest.sources.append(photoSet)
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

        removeStoredFiles(for: [source])
        return updatedManifest
    }

    func storedFileURLs(for source: AIGenerationLabSource) -> [URL] {
        source.storedFilenames.map { filename in
            sourcesDirectoryURL.appendingPathComponent(filename)
        }
    }

    func saveReport(_ report: AIGenerationLabRunReport) throws {
        try prepareDirectories()
        let data = try encoder.encode(report)
        let reportURL = reportsDirectoryURL.appendingPathComponent(
            "run-\(report.id.uuidString).json"
        )
        try data.write(to: reportURL, options: [.atomic, .completeFileProtection])
        try data.write(to: latestReportURL, options: [.atomic, .completeFileProtection])
    }

    func loadLatestReport() throws -> AIGenerationLabRunReport? {
        try prepareDirectories()
        guard fileManager.fileExists(atPath: latestReportURL.path) else { return nil }
        let report = try decoder.decode(
            AIGenerationLabRunReport.self,
            from: Data(contentsOf: latestReportURL)
        )
        guard report.schemaVersion == AIGenerationLabRunReport.currentSchemaVersion else {
            throw AIGenerationLabStoreError.unsupportedManifest
        }
        return report
    }

    func encodedReport(_ report: AIGenerationLabRunReport) throws -> Data {
        try encoder.encode(report)
    }

    private func persistPDFSource(
        data: Data,
        displayName: String,
        pageCount: Int
    ) throws -> AIGenerationLabSource {
        let id = UUID()
        let storedFilename = id.uuidString + ".pdf"
        let destinationURL = sourcesDirectoryURL.appendingPathComponent(storedFilename)
        try data.write(to: destinationURL, options: [.atomic, .completeFileProtection])

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDestinationURL = destinationURL
        try? mutableDestinationURL.setResourceValues(resourceValues)

        return AIGenerationLabSource(
            id: id,
            kind: .pdf,
            displayName: displayName.isEmpty ? storedFilename : displayName,
            storedFilenames: [storedFilename],
            byteCount: Int64(data.count),
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            pageCount: pageCount,
            imageCount: nil,
            addedAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        )
    }

    private func persistPhotoSet(
        _ imports: [AIGenerationLabImageImport]
    ) throws -> AIGenerationLabSource {
        guard !imports.isEmpty else { throw AIGenerationLabStoreError.invalidImage }
        guard imports.allSatisfy({ Self.imagePixelSize(from: $0.data) != nil }) else {
            throw AIGenerationLabStoreError.invalidImage
        }

        let id = UUID()
        var storedFilenames: [String] = []
        do {
            for (index, imageImport) in imports.enumerated() {
                let filename = "\(id.uuidString)-\(index + 1).\(Self.safeExtension(imageImport.filenameExtension))"
                let destinationURL = sourcesDirectoryURL.appendingPathComponent(filename)
                try imageImport.data.write(
                    to: destinationURL,
                    options: [.atomic, .completeFileProtection]
                )
                storedFilenames.append(filename)
            }
        } catch {
            for filename in storedFilenames {
                try? fileManager.removeItem(
                    at: sourcesDirectoryURL.appendingPathComponent(filename)
                )
            }
            throw error
        }

        let firstName = imports.first?.displayName ?? id.uuidString
        let displayName: String
        if let lastName = imports.last?.displayName, imports.count > 1 {
            displayName = "\(firstName) – \(lastName)"
        } else {
            displayName = firstName
        }
        return AIGenerationLabSource(
            id: id,
            kind: .photos,
            displayName: displayName,
            storedFilenames: storedFilenames,
            byteCount: Int64(imports.reduce(0) { $0 + $1.data.count }),
            sha256: Self.photoSetSHA256(imports.map(\.data)),
            pageCount: nil,
            imageCount: imports.count,
            addedAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        )
    }

    private func prepareDirectories() throws {
        try fileManager.createDirectory(
            at: sourcesDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try fileManager.createDirectory(
            at: reportsDirectoryURL,
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
            for filename in source.storedFilenames {
                let storedURL = sourcesDirectoryURL.appendingPathComponent(filename)
                try? fileManager.removeItem(at: storedURL)
            }
        }
    }

    private static func photoSetSHA256(_ items: [Data]) -> String {
        var hasher = SHA256()
        for data in items {
            var length = UInt64(data.count).bigEndian
            withUnsafeBytes(of: &length) { bytes in
                hasher.update(data: Data(bytes))
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
    private(set) var isRunning = false
    private(set) var hasLoaded = false
    private(set) var maximumTargetCardCount = SubscriptionManager.premiumMaxCardsPerGeneration
    private(set) var runProgress: AIGenerationLabRunProgress?
    private(set) var completedCaseResults: [AIGenerationLabCaseResult] = []
    private(set) var latestReport: AIGenerationLabRunReport?
    private(set) var didCopyLatestReport = false
    var targetCardCount = 30 {
        didSet {
            let clampedValue = min(max(targetCardCount, 5), maximumTargetCardCount)
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
    @ObservationIgnored private let runner: AIGenerationLabRunner
    @ObservationIgnored private let subscriptionManager: SubscriptionManager
    @ObservationIgnored private var persistenceTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var copyFeedbackTask: Task<Void, Never>?
    @ObservationIgnored private var isApplyingManifest = false

    init(
        store: AIGenerationLabCorpusStore = .shared,
        runner: AIGenerationLabRunner? = nil,
        subscriptionManager: SubscriptionManager? = nil
    ) {
        self.store = store
        self.runner = runner ?? AIGenerationLabRunner()
        self.subscriptionManager = subscriptionManager ?? .shared
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
            latestReport = try await store.loadLatestReport()
            completedCaseResults = latestReport?.cases ?? []
            await refreshGenerationAccess()
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
            let existingImageCount = sources.lazy
                .filter { $0.kind == .photos }
                .compactMap(\.imageCount)
                .reduce(0, +)

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

    var canStartRun: Bool {
        hasLoaded && !sources.isEmpty && !isWorking && !isRunning
    }

    func startRun() {
        guard canStartRun else { return }
        persistenceTask?.cancel()
        didCopyLatestReport = false
        let sourceSnapshot = sources
        let targetSnapshot = targetCardCount
        let optionsSnapshot = options

        runTask = Task { [weak self] in
            guard let self else { return }
            await executeRun(
                sources: sourceSnapshot,
                targetCardCount: targetSnapshot,
                options: optionsSnapshot
            )
        }
    }

    func cancelRun() {
        runTask?.cancel()
    }

    func copyLatestReport() async {
        guard let latestReport else { return }
        do {
            let data = try await store.encodedReport(latestReport)
            guard let string = String(data: data, encoding: .utf8) else { return }
            UIPasteboard.general.string = string
            didCopyLatestReport = true
            copyFeedbackTask?.cancel()
            copyFeedbackTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.didCopyLatestReport = false
            }
        } catch {
            present(error)
        }
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

    private func executeRun(
        sources: [AIGenerationLabSource],
        targetCardCount: Int,
        options: AIGenerationOptions
    ) async {
        isRunning = true
        completedCaseResults = []
        latestReport = nil
        defer {
            isRunning = false
            runProgress = nil
            runTask = nil
        }

        await refreshGenerationAccess()
        guard targetCardCount <= maximumTargetCardCount else {
            present(AIGenerationLabExecutionError.targetExceedsPlan)
            return
        }
        if let message = subscriptionManager.aiGenerationLimitMessage(
            locale: AppPreferences.persistedResolvedLocale
        ) {
            present(AIGenerationLabExecutionError.accessDenied(message))
            return
        }

        let runID = UUID()
        let startedAt = Self.epochMilliseconds()
        do {
            try await store.saveManifest(
                AIGenerationLabManifest(
                    sources: sources,
                    targetCardCount: targetCardCount,
                    options: options
                )
            )

            for (index, source) in sources.enumerated() {
                try Task.checkCancellation()
                let storedURLs = await store.storedFileURLs(for: source)
                let result = try await runner.runCase(
                    source: source,
                    storedFileURLs: storedURLs,
                    targetCardCount: targetCardCount,
                    options: options,
                    caseIndex: index + 1,
                    caseCount: sources.count
                ) { [weak self] progress in
                    self?.runProgress = progress
                }
                completedCaseResults.append(result)
                try await persistRunReport(
                    id: runID,
                    startedAt: startedAt,
                    targetCardCount: targetCardCount,
                    options: options
                )
            }
        } catch is CancellationError {
            if !completedCaseResults.isEmpty {
                try? await persistRunReport(
                    id: runID,
                    startedAt: startedAt,
                    targetCardCount: targetCardCount,
                    options: options
                )
            }
        } catch {
            present(error)
        }
    }

    private func persistRunReport(
        id: UUID,
        startedAt: Int64,
        targetCardCount: Int,
        options: AIGenerationOptions
    ) async throws {
        let info = Bundle.main.infoDictionary
        let report = AIGenerationLabRunReport(
            id: id,
            startedAtEpochMilliseconds: startedAt,
            finishedAtEpochMilliseconds: Self.epochMilliseconds(),
            targetCardCountPerSource: targetCardCount,
            options: options,
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "",
            appBuild: info?["CFBundleVersion"] as? String ?? "",
            deviceModel: UIDevice.current.model,
            operatingSystem: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            cases: completedCaseResults
        )
        try await store.saveReport(report)
        latestReport = report
    }

    private func refreshGenerationAccess() async {
        await subscriptionManager.refresh()
        maximumTargetCardCount = subscriptionManager.maxCardsPerGeneration
        if targetCardCount > maximumTargetCardCount {
            targetCardCount = maximumTargetCardCount
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

    private static func epochMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }
}

nonisolated enum AIGenerationLabExecutionError: LocalizedError {
    case targetExceedsPlan
    case accessDenied(String)

    var errorDescription: String? {
        switch self {
        case .targetExceedsPlan:
            return "The selected card target exceeds the active plan."
        case .accessDenied(let message):
            return message
        }
    }
}
#endif
