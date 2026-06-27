//
//  SubscriptionManagerQuotaTests.swift
//  QuizFlashTests
//

import XCTest
@testable import QuizFlash

@MainActor
final class SubscriptionManagerQuotaTests: XCTestCase {
    func testFreeQuotaDoesNotRegressAfterAuthoritativeLimitReachedState() {
        let manager = SubscriptionManager()

        manager.applyCloudAIQuotaState(CloudAIQuotaState(
            premium: false,
            freeGenerationsUsed: 5,
            freeGenerationsLimit: 5,
            monthlyCostMicroUSD: 0
        ))

        manager.applyCloudAIQuotaState(CloudAIQuotaState(
            premium: false,
            freeGenerationsUsed: 0,
            freeGenerationsLimit: 5,
            monthlyCostMicroUSD: 0
        ))

        XCTAssertEqual(manager.freeGenerationsUsed, 5)
        XCTAssertEqual(manager.freeGenerationsLimit, 5)
    }
}
