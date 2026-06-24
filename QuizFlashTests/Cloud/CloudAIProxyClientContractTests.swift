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
