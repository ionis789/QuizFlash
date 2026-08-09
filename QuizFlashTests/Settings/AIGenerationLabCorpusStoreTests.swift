#if DEBUG
import CryptoKit
import UIKit
import XCTest
@testable import QuizFlash

@MainActor
final class AIGenerationLabCorpusStoreTests: XCTestCase {
    func testMixedImportsPersistExactOrderAndMetadata() async throws {
        let rootURL = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AIGenerationLabCorpusStore(rootDirectoryURL: rootURL)
        let pdfData = makePDFData()
        let pdfURL = rootURL.appendingPathComponent("reference.pdf")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try pdfData.write(to: pdfURL)

        var manifest = try await store.importPDFs(
            from: [pdfURL],
            appendingTo: AIGenerationLabManifest()
        )

        let imageData = try XCTUnwrap(makeImageData(color: .purple))
        manifest = try await store.importImages(
            [
                AIGenerationLabImageImport(
                    data: imageData,
                    displayName: "IMG-001",
                    filenameExtension: "png"
                )
            ],
            appendingTo: manifest
        )

        XCTAssertEqual(manifest.sources.map(\.kind), [.pdf, .photos])
        XCTAssertEqual(manifest.sources.map(\.displayName), ["reference", "IMG-001"])
        XCTAssertEqual(manifest.sources[0].pageCount, 1)
        XCTAssertEqual(manifest.sources[1].imageCount, 1)
        XCTAssertEqual(manifest.sources[0].sha256, sha256(pdfData))
        XCTAssertEqual(manifest.sources[1].sha256, sha256(imageData))

        let reloaded = try await store.loadManifest()
        XCTAssertEqual(reloaded, manifest)

        for source in manifest.sources {
            let storedURLs = await store.storedFileURLs(for: source)
            XCTAssertEqual(storedURLs.count, source.storedFilenames.count)
            XCTAssertTrue(storedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        }
    }

    func testMoveAndRemovePersistWithoutChangingRemainingSource() async throws {
        let rootURL = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AIGenerationLabCorpusStore(rootDirectoryURL: rootURL)
        let firstData = try XCTUnwrap(makeImageData(color: .red))
        let secondData = try XCTUnwrap(makeImageData(color: .blue))
        var manifest = try await store.importImages(
            [
                AIGenerationLabImageImport(
                    data: firstData,
                    displayName: "IMG-001",
                    filenameExtension: "png"
                )
            ],
            appendingTo: AIGenerationLabManifest()
        )
        manifest = try await store.importImages(
            [
                AIGenerationLabImageImport(
                    data: secondData,
                    displayName: "IMG-002",
                    filenameExtension: "png"
                )
            ],
            appendingTo: manifest
        )

        let firstSource = manifest.sources[0]
        let secondSource = manifest.sources[1]
        manifest = try await store.moveSource(id: secondSource.id, by: -1, in: manifest)
        XCTAssertEqual(manifest.sources.map(\.id), [secondSource.id, firstSource.id])

        let removedURLs = await store.storedFileURLs(for: secondSource)
        manifest = try await store.removeSource(id: secondSource.id, from: manifest)

        XCTAssertEqual(manifest.sources.map(\.id), [firstSource.id])
        XCTAssertTrue(removedURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        let reloaded = try await store.loadManifest()
        XCTAssertEqual(reloaded, manifest)
    }

    func testOnePhotoSelectionPersistsAsOneOrderedGenerationCase() async throws {
        let rootURL = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AIGenerationLabCorpusStore(rootDirectoryURL: rootURL)
        let firstData = try XCTUnwrap(makeImageData(color: .red))
        let secondData = try XCTUnwrap(makeImageData(color: .blue))
        let manifest = try await store.importImages(
            [
                AIGenerationLabImageImport(
                    data: firstData,
                    displayName: "IMG-001",
                    filenameExtension: "png"
                ),
                AIGenerationLabImageImport(
                    data: secondData,
                    displayName: "IMG-002",
                    filenameExtension: "png"
                )
            ],
            appendingTo: AIGenerationLabManifest()
        )

        XCTAssertEqual(manifest.sources.count, 1)
        XCTAssertEqual(manifest.sources[0].kind, .photos)
        XCTAssertEqual(manifest.sources[0].imageCount, 2)
        let storedURLs = await store.storedFileURLs(for: manifest.sources[0])
        XCTAssertEqual(try storedURLs.map(Data.init(contentsOf:)), [firstData, secondData])
    }

    func testPDFImageMirrorsUsePhotoSourcesAndRemainIdempotent() async throws {
        let rootURL = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AIGenerationLabCorpusStore(rootDirectoryURL: rootURL)
        let pdfURL = rootURL.appendingPathComponent("reference.pdf")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try makePDFData().write(to: pdfURL)

        var manifest = try await store.importPDFs(
            from: [pdfURL],
            appendingTo: AIGenerationLabManifest()
        )
        manifest = try await store.importPDFImageMirrors(appendingTo: manifest)

        XCTAssertEqual(manifest.sources.map(\.kind), [.pdf, .photos])
        XCTAssertEqual(manifest.sources[1].displayName, "reference · OCR")
        XCTAssertEqual(manifest.sources[1].imageCount, 1)
        let mirrorID = manifest.sources[1].id
        let mirrorURLs = await store.storedFileURLs(for: manifest.sources[1])
        XCTAssertEqual(mirrorURLs.count, 1)
        XCTAssertNotNil(UIImage(data: try Data(contentsOf: mirrorURLs[0])))

        manifest = try await store.importPDFImageMirrors(appendingTo: manifest)
        XCTAssertEqual(manifest.sources.count, 2)
        XCTAssertEqual(manifest.sources[1].id, mirrorID)
    }

    func testGenerationConfigurationRoundTripsExactly() async throws {
        let rootURL = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AIGenerationLabCorpusStore(rootDirectoryURL: rootURL)
        let language = AIGenerationLanguageHint(languageCode: "test", displayName: "Test")
        let manifest = AIGenerationLabManifest(
            targetCardCount: 55,
            options: AIGenerationOptions(
                cardType: .quiz,
                cardLevel: .simple,
                outputLanguageMode: .manual,
                manualOutputLanguage: language,
                userInstructions: "Keep this exact instruction."
            )
        )

        try await store.saveManifest(manifest)

        let reloaded = try await store.loadManifest()
        XCTAssertEqual(reloaded, manifest)
    }

    func testLatestRunReportPersistsFullCardsAndMetrics() async throws {
        let rootURL = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AIGenerationLabCorpusStore(rootDirectoryURL: rootURL)
        let sourceID = UUID()
        let caseResult = AIGenerationLabCaseResult(
            id: UUID(),
            sourceID: sourceID,
            sourceKind: .pdf,
            sourceName: "reference",
            sourceSHA256: "digest",
            status: .succeeded,
            targetCardCount: 1,
            generatedCardCount: 1,
            shortfallCount: 0,
            batchCount: 1,
            objectiveCoverageCount: 1,
            uniquePromptCount: 1,
            duplicatePromptCount: 0,
            sourceSegmentCount: 2,
            sourceCharacterCount: 120,
            suggestedTitle: "Title",
            detectedLanguageCode: "code",
            promptVersion: "version",
            traceRunID: UUID(),
            timings: AIGenerationLabCaseTimings(
                preparationMilliseconds: 10,
                authorizationMilliseconds: 20,
                blueprintMilliseconds: 30,
                firstCardMilliseconds: 40,
                cardGenerationMilliseconds: 50,
                finalizationMilliseconds: 60,
                totalMilliseconds: 170
            ),
            errorMessage: nil,
            sourceSegments: [
                AITextSourceSegment(index: 0, label: "Segment 1", text: "Source text")
            ],
            blueprint: nil,
            generatedCards: [
                AIGenerationLabGeneratedCard(
                    index: 1,
                    objectiveID: nil,
                    card: AIFlashcard(question: "Question", answer: "Answer")
                )
            ]
        )
        let report = AIGenerationLabRunReport(
            startedAtEpochMilliseconds: 1,
            finishedAtEpochMilliseconds: 2,
            targetCardCountPerSource: 1,
            options: AIGenerationOptions(),
            appVersion: "1",
            appBuild: "1",
            deviceModel: "Device",
            operatingSystem: "OS",
            cases: [caseResult]
        )

        try await store.saveReport(report)

        let reloaded = try XCTUnwrap(try await store.loadLatestReport())
        XCTAssertEqual(reloaded.schemaVersion, AIGenerationLabRunReport.currentSchemaVersion)
        XCTAssertEqual(reloaded.id, report.id)
        XCTAssertEqual(reloaded.cases.count, 1)
        XCTAssertEqual(reloaded.cases[0].sourceID, sourceID)
        XCTAssertEqual(reloaded.cases[0].timings.totalMilliseconds, 170)
        XCTAssertEqual(reloaded.cases[0].sourceSegments.map(\.text), ["Source text"])
        XCTAssertEqual(reloaded.cases[0].generatedCards.count, 1)
        XCTAssertEqual(reloaded.cases[0].generatedCards[0].card.question, "Question")
        XCTAssertEqual(
            try await store.encodedReport(reloaded),
            try await store.encodedReport(report)
        )
    }

    func testUnsupportedManifestIsRejected() async throws {
        let rootURL = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let store = AIGenerationLabCorpusStore(rootDirectoryURL: rootURL)
        let manifest = AIGenerationLabManifest(schemaVersion: 999)

        do {
            try await store.saveManifest(manifest)
            XCTFail("Expected unsupported manifest error")
        } catch AIGenerationLabStoreError.unsupportedManifest {
            // Expected strict current-contract behavior.
        }
    }

    private func makeTemporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AIGenerationLabTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makePDFData() -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        return renderer.pdfData { context in
            context.beginPage()
            NSString(string: "Corpus").draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
        }
    }

    private func makeImageData(color: UIColor) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 24, height: 16),
            format: format
        )
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
        }.pngData()
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
