import XCTest
@testable import QuizFlash

final class AIDebugTraceStoreTests: XCTestCase {
    func testFailedBlueprintRunIsPersistedAsCopyableJSON() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quizflash-ai-trace-tests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "quizflash-ai-trace-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated user defaults")
            return
        }
        defaults.set(true, forKey: AIDebugTracePreferenceKeys.debugTracingEnabled)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = AIDebugTraceStore(
            rootDirectoryURL: rootURL,
            userDefaults: defaults
        )
        let descriptor = AIDebugTraceRunDescriptor(
            kind: .generation,
            targetType: "flashcards",
            sourceKind: "pdf",
            targetCount: 30,
            sourceCount: 12,
            providerName: "provider",
            modelName: "model",
            metadata: ["prompt_version": "test"]
        )
        guard let scope = await store.startRun(descriptor) else {
            XCTFail("Expected development trace scope")
            return
        }

        await store.record(
            stage: .blueprintValidationFailed,
            message: "Blueprint validation requires semantic repair.",
            scope: scope,
            metadata: ["issues": "duplicate_objective"]
        )
        await store.finishRun(
            scope: scope,
            succeeded: false,
            error: AIServiceError.invalidResponse
        )

        let runs = await store.listRuns()
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].kind, .generation)
        XCTAssertEqual(runs[0].status, "failed")
        XCTAssertEqual(runs[0].targetCount, 30)

        let detail = await store.loadRunDetail(id: runs[0].id)
        XCTAssertNotNil(detail)
        XCTAssertTrue(detail?.jsonString.contains("blueprintValidationFailed") == true)
        XCTAssertTrue(detail?.jsonString.contains("duplicate_objective") == true)
        XCTAssertTrue(detail?.jsonString.contains("runFailed") == true)
    }

    func testNestedDebugRunsReuseTheOuterGenerationTrace() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quizflash-ai-trace-tests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "quizflash-ai-trace-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated user defaults")
            return
        }
        defaults.set(true, forKey: AIDebugTracePreferenceKeys.debugTracingEnabled)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = AIDebugTraceStore(
            rootDirectoryURL: rootURL,
            userDefaults: defaults
        )
        let service = AIFlashcardService(
            provider: AIProviderProfile(
                name: "Test Provider",
                endpointURLString: "https://example.invalid/v1",
                apiKey: "test",
                textModel: "test-text",
                visionModel: "test-vision"
            ),
            debugTraceStore: store
        )

        let value = try await service.withDebugRun(
            kind: .generation,
            targetType: "flashcards",
            sourceKind: "pdf",
            targetCount: 30,
            sourceCount: 12
        ) {
            try await service.withDebugRun(
                kind: .utility,
                targetType: "blueprint",
                sourceKind: "segments"
            ) {
                await service.trace(
                    .blueprintDirect,
                    "Building a source blueprint in one request."
                )
                return true
            }
        }

        XCTAssertTrue(value)
        let runs = await store.listRuns()
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].kind, .generation)
        XCTAssertEqual(runs[0].status, "completed")
        let detail = await store.loadRunDetail(id: runs[0].id)
        XCTAssertTrue(detail?.jsonString.contains("blueprintDirect") == true)
        await Task.yield()
    }
}
