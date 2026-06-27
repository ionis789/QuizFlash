//
//  SubscriptionManagerQuotaTests.swift
//  QuizFlashTests
//

import XCTest
@testable import QuizFlash

@MainActor
final class SubscriptionManagerQuotaTests: XCTestCase {
    func testFreeQuotaAcceptsAuthoritativeReset() {
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

        XCTAssertEqual(manager.freeGenerationsUsed, 0)
        XCTAssertEqual(manager.freeGenerationsLimit, 5)
    }

    func testFirestoreDowngradeReplacesCachedPremiumState() {
        let manager = SubscriptionManager()

        manager.applyCloudAIQuotaState(CloudAIQuotaState(
            premium: true,
            freeGenerationsUsed: nil,
            freeGenerationsLimit: nil,
            monthlyCostMicroUSD: 50
        ))
        manager.applyCloudAIQuotaState(CloudAIQuotaState(
            premium: false,
            freeGenerationsUsed: 2,
            freeGenerationsLimit: 5,
            monthlyCostMicroUSD: 50
        ))

        XCTAssertFalse(manager.isPremium)
        XCTAssertEqual(manager.freeGenerationsUsed, 2)
        XCTAssertEqual(manager.freeGenerationsLimit, 5)
    }
}
