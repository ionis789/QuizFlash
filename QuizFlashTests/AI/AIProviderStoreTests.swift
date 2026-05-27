//
//  AIProviderStoreTests.swift
//  QuizFlashTests
//
//  Covers persistence and recovery behavior for editable AI provider profiles.
//

import Foundation
import XCTest
@testable import QuizFlash

@MainActor
final class AIProviderStoreTests: XCTestCase {
    func testUpsertAndReloadPersistsProfilesAndActiveSelection() throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIProviderStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("provider_profiles.json")
        let store = AIProviderStore(fileURL: fileURL, fileManager: .default)

        let customProfile = AIProviderProfile(
            name: "Local Provider",
            endpointURLString: "https://example.com/v1",
            apiKey: "secret-1234",
            textModel: "text-model",
            visionModel: "vision-model",
            httpReferer: "https://quizflash.app",
            xTitle: "QuizFlash",
            extraBodyJSONString: "{\"reasoning_effort\":\"low\"}"
        )

        store.upsertProfile(customProfile, makeActive: true)

        let reloadedStore = AIProviderStore(fileURL: fileURL, fileManager: .default)

        XCTAssertEqual(reloadedStore.activeProfileID, customProfile.id)
        XCTAssertEqual(reloadedStore.activeProfile?.name, "Local Provider")
        XCTAssertEqual(reloadedStore.activeProfile?.trimmedAPIKey, "secret-1234")
        XCTAssertEqual(reloadedStore.profiles.count, 4)
        XCTAssertTrue(reloadedStore.profiles.contains(where: { $0.id == customProfile.id }))
    }

    func testDeleteActiveProfilePromotesFallbackAndKeepsOneProfileMinimum() throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIProviderStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("provider_profiles.json")
        let store = AIProviderStore(fileURL: fileURL, fileManager: .default)

        let originalProfiles = store.profiles
        let originalActiveID = try XCTUnwrap(store.activeProfileID)

        store.deleteProfile(id: originalActiveID)

        XCTAssertEqual(store.profiles.count, originalProfiles.count - 1)
        XCTAssertNotEqual(store.activeProfileID, originalActiveID)
        XCTAssertNotNil(store.activeProfile)

        while store.profiles.count > 1 {
            let removableID = try XCTUnwrap(store.profiles.last?.id)
            store.deleteProfile(id: removableID)
        }

        let lastProfileID = try XCTUnwrap(store.profiles.first?.id)
        store.deleteProfile(id: lastProfileID)

        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.activeProfileID, lastProfileID)
    }

    func testCorruptedPayloadFallsBackToDefaultProfiles() throws {
        let directoryURL = try TestFileSystemFactory.makeTemporaryDirectory(prefix: "AIProviderStoreTests")
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let fileURL = directoryURL.appendingPathComponent("provider_profiles.json")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Data("not-json".utf8).write(to: fileURL, options: .atomic)

        let store = AIProviderStore(fileURL: fileURL, fileManager: .default)

        XCTAssertEqual(store.profiles.map(\.name), ["DeepSeek", "OpenAI", "OpenRouter"])
        XCTAssertEqual(store.activeProfileID, store.profiles.first?.id)

        let reloadedStore = AIProviderStore(fileURL: fileURL, fileManager: .default)
        XCTAssertEqual(reloadedStore.profiles.count, 3)
        XCTAssertEqual(reloadedStore.activeProfile?.name, "DeepSeek")
    }
}
