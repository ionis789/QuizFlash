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

        XCTAssertEqual(manifest.sources.map(\.kind), [.pdf, .image])
        XCTAssertEqual(manifest.sources.map(\.displayName), ["reference", "IMG-001"])
        XCTAssertEqual(manifest.sources[0].pageCount, 1)
        XCTAssertEqual(manifest.sources[1].pixelWidth, 24)
        XCTAssertEqual(manifest.sources[1].pixelHeight, 16)
        XCTAssertEqual(manifest.sources[0].sha256, sha256(pdfData))
        XCTAssertEqual(manifest.sources[1].sha256, sha256(imageData))

        let reloaded = try await store.loadManifest()
        XCTAssertEqual(reloaded, manifest)

        for source in manifest.sources {
            let storedURL = await store.storedFileURL(for: source)
            XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
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
                ),
                AIGenerationLabImageImport(
                    data: secondData,
                    displayName: "IMG-002",
                    filenameExtension: "png"
                )
            ],
            appendingTo: AIGenerationLabManifest()
        )

        let firstSource = manifest.sources[0]
        let secondSource = manifest.sources[1]
        manifest = try await store.moveSource(id: secondSource.id, by: -1, in: manifest)
        XCTAssertEqual(manifest.sources.map(\.id), [secondSource.id, firstSource.id])

        let removedURL = await store.storedFileURL(for: secondSource)
        manifest = try await store.removeSource(id: secondSource.id, from: manifest)

        XCTAssertEqual(manifest.sources.map(\.id), [firstSource.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedURL.path))
        let reloaded = try await store.loadManifest()
        XCTAssertEqual(reloaded, manifest)
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
