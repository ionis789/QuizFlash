//
//  CloudAIProxyClientContractTests.swift
//  QuizFlashTests
//

import XCTest
@testable import QuizFlash

final class CloudAIProxyClientContractTests: XCTestCase {
    func testDecodesWorkerGenerationID() throws {
        let payload = Data(
            """
            {
              "generationId": "generation-123",
              "sessionToken": "session-token",
              "targetCards": 5,
              "quota": {
                "premium": false,
                "freeGenerationsUsed": 1,
                "freeGenerationsLimit": 5,
                "monthlyCostMicroUSD": 0
              },
              "promptVersion": "v1",
              "promptHash": "hash"
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(StartResponse.self, from: payload)

        XCTAssertEqual(response.generationID, "generation-123")
        XCTAssertEqual(response.sessionToken, "session-token")
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
