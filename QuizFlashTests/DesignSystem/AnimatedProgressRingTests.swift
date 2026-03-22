//
//  AnimatedProgressRingTests.swift
//  QuizFlashTests
//
//  Verifies the shared progress ring chooses stable transitions.
//

import XCTest
@testable import QuizFlash

final class AnimatedProgressRingTests: XCTestCase {
    func testTransitionPlanDisablesGlowWhenAnimatingToZero() {
        let plan = AnimatedProgressRingTransitionPlan.make(previousProgress: 0.62, newProgress: 0)

        XCTAssertEqual(plan.targetProgress, 0, accuracy: 0.001)
        XCTAssertEqual(plan.style, .zeroSettle)
        XCTAssertFalse(plan.shouldGlow)
    }

    func testTransitionPlanKeepsSettleAnimationForPositiveTargets() {
        let plan = AnimatedProgressRingTransitionPlan.make(previousProgress: 0.18, newProgress: 0.64)

        XCTAssertEqual(plan.targetProgress, 0.64, accuracy: 0.001)
        XCTAssertEqual(plan.style, .settle)
        XCTAssertTrue(plan.shouldGlow)
    }
}
