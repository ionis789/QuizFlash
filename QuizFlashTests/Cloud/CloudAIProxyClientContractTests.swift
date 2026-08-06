//
//  CloudAIProxyClientContractTests.swift
//  QuizFlashTests
//

import XCTest
@testable import QuizFlash

final class CloudAIProxyClientContractTests: XCTestCase {
    @MainActor
    func testPendingFinalizationCompletesBeforeNextStartCanContinue() async throws {
        let coordinator = CloudAIGenerationFinalizationCoordinator()
        let gate = CloudFinalizationTestGate()
        let state = CloudFinalizationTestState()

        let finalization = coordinator.register(generationID: "generation") {
            await gate.wait()
        }
        let startBarrier = Task { @MainActor in
            try await coordinator.resolveBeforeStartingGeneration()
            state.didResolveStart = true
        }

        await Task.yield()
        XCTAssertFalse(state.didResolveStart)

        await gate.open()
        _ = await finalization.value
        try await startBarrier.value
        XCTAssertTrue(state.didResolveStart)
    }

    @MainActor
    func testFailedFinalizationIsRetriedBeforeNextStart() async throws {
        let coordinator = CloudAIGenerationFinalizationCoordinator()
        let state = CloudFinalizationTestState()

        let firstAttempt = coordinator.register(generationID: "generation") {
            state.attemptCount += 1
            if state.attemptCount == 1 {
                throw CloudFinalizationTestError.expectedFailure
            }
        }

        let firstResult = await firstAttempt.value
        if case .success = firstResult {
            XCTFail("Expected the first finalization attempt to fail")
        }

        try await coordinator.resolveBeforeStartingGeneration()
        XCTAssertEqual(state.attemptCount, 2)
    }

    func testDecodesWorkerGenerationID() throws {
        let payload = Data(
            """
            {
              "generationId": "generation-123",
              "sessionToken": "session-token",
              "targetCards": 5,
              "usageQuota": {
                "premium": false,
                "freeGenerationsUsed": 1,
                "freeGenerationsLimit": 5,
                "monthlyCostMicroUSD": 0,
                "limitMicroUSD": null,
                "consumedMicroUSD": 0,
                "reservedMicroUSD": 0,
                "availableMicroUSD": null,
                "percent": null
              },
              "promptVersion": "v1",
              "promptHash": "hash"
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(StartResponse.self, from: payload)

        XCTAssertEqual(response.generationID, "generation-123")
        XCTAssertEqual(response.sessionToken, "session-token")
        XCTAssertEqual(response.usageQuota.freeGenerationsUsed, 1)
    }

    func testDecodesLegacyQuotaField() throws {
        let payload = Data(
            """
            {
              "generationId": "generation-123",
              "sessionToken": "session-token",
              "targetCards": 5,
              "quota": {
                "premium": true,
                "freeGenerationsUsed": null,
                "freeGenerationsLimit": null,
                "monthlyCostMicroUSD": 12000,
                "limitMicroUSD": 20000,
                "consumedMicroUSD": 12000,
                "reservedMicroUSD": 0,
                "availableMicroUSD": 8000,
                "percent": 0.6
              },
              "promptVersion": "v1",
              "promptHash": "hash"
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(StartResponse.self, from: payload)

        XCTAssertTrue(response.usageQuota.premium)
        XCTAssertEqual(response.usageQuota.usageProgress, 0.6, accuracy: 0.001)
    }

    func testEncodesWorkerGenerationIDForSessionCompletion() throws {
        let finishData = try JSONEncoder().encode(
            FinishRequest(generationID: "generation-123", sessionToken: "session-token", validatedCards: 5)
        )
        let failData = try JSONEncoder().encode(
            FailRequest(generationID: "generation-123", sessionToken: "session-token")
        )

        let finish = try JSONSerialization.jsonObject(with: finishData) as? [String: Any]
        let failure = try JSONSerialization.jsonObject(with: failData) as? [String: Any]

        XCTAssertEqual(finish?["generationId"] as? String, "generation-123")
        XCTAssertNil(finish?["generationID"])
        XCTAssertEqual(failure?["generationId"] as? String, "generation-123")
        XCTAssertNil(failure?["generationID"])
    }
}

private enum CloudFinalizationTestError: Error {
    case expectedFailure
}

@MainActor
private final class CloudFinalizationTestState {
    var didResolveStart = false
    var attemptCount = 0
}

private actor CloudFinalizationTestGate {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
