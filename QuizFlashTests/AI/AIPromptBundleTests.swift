//
//  AIPromptBundleTests.swift
//  QuizFlashTests
//

import XCTest
@testable import QuizFlash

final class AIPromptBundleTests: XCTestCase {
    func testPromptBundleValidatesCanonicalHash() throws {
        let templates = Self.validTemplates
        let bundle = AIPromptBundle(
            version: "v1",
            hash: try AIPromptBundle.hashTemplates(templates),
            status: "active",
            templates: templates
        )

        XCTAssertNoThrow(try bundle.validated())
    }

    func testPromptBundleRejectsHashMismatch() throws {
        let bundle = AIPromptBundle(
            version: "v1",
            hash: "wrong",
            status: "active",
            templates: Self.validTemplates
        )

        XCTAssertThrowsError(try bundle.validated())
    }

    func testPromptBundleCacheStoresAndReloadsValidatedBundle() async throws {
        let suiteName = "AIPromptBundleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cache = AIPromptBundleCache(defaults: defaults)
        let templates = Self.validTemplates
        let bundle = AIPromptBundle(
            version: "v1",
            hash: try AIPromptBundle.hashTemplates(templates),
            status: "active",
            templates: templates
        )

        _ = try await cache.store(bundle)
        let reloaded = try await cache.bundle(version: bundle.version, hash: bundle.hash)

        XCTAssertEqual(reloaded, bundle)
    }

    private static let validTemplates = AIPromptBundleFixture.templates

}
