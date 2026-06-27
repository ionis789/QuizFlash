//
//  TabBarScrollAutoHideResolverTests.swift
//  QuizFlashTests
//
//  Guards the custom tab bar auto-hide resolver against scroll-direction regressions.
//

import XCTest
@testable import QuizFlash

final class TabBarScrollAutoHideResolverTests: XCTestCase {
    func testScrollingDownHidesAfterCumulativeThreshold() {
        var resolver = TabBarScrollAutoHideResolver(
            downwardHideThreshold: 10,
            upwardRevealThreshold: 1,
            topRevealTolerance: 1
        )

        XCTAssertNil(
            resolver.handle(
                offset: 0,
                minOffset: 0,
                canHide: false,
                canShow: false
            )
        )
        XCTAssertNil(
            resolver.handle(
                offset: 4,
                minOffset: 0,
                canHide: true,
                canShow: true
            )
        )

        XCTAssertEqual(
            resolver.handle(
                offset: 12,
                minOffset: 0,
                canHide: true,
                canShow: true
            ),
            .hide
        )
        XCTAssertTrue(resolver.isHidden)
    }

    func testSmallestUpwardDragRevealsImmediatelyWhenHidden() {
        var resolver = TabBarScrollAutoHideResolver(
            downwardHideThreshold: 10,
            upwardRevealThreshold: 1,
            topRevealTolerance: 1
        )

        _ = resolver.handle(offset: 0, minOffset: 0, canHide: false, canShow: false)
        _ = resolver.handle(offset: 12, minOffset: 0, canHide: true, canShow: true)

        XCTAssertEqual(
            resolver.handle(
                offset: 11,
                minOffset: 0,
                canHide: true,
                canShow: true
            ),
            .show
        )
        XCTAssertFalse(resolver.isHidden)
    }

    func testUpwardDecelerationDoesNotRevealUntilUserTouchesAgain() {
        var resolver = TabBarScrollAutoHideResolver(
            downwardHideThreshold: 10,
            upwardRevealThreshold: 1,
            topRevealTolerance: 1
        )

        _ = resolver.handle(offset: 0, minOffset: 0, canHide: false, canShow: false)
        _ = resolver.handle(offset: 16, minOffset: 0, canHide: true, canShow: true)

        XCTAssertNil(
            resolver.handle(
                offset: 14,
                minOffset: 0,
                canHide: true,
                canShow: false
            )
        )
        XCTAssertTrue(resolver.isHidden)

        XCTAssertEqual(
            resolver.handle(
                offset: 13,
                minOffset: 0,
                canHide: true,
                canShow: true
            ),
            .show
        )
        XCTAssertFalse(resolver.isHidden)
    }

    func testResetRevealsBarWhenAutoHideWasActive() {
        var resolver = TabBarScrollAutoHideResolver(
            downwardHideThreshold: 10,
            upwardRevealThreshold: 1,
            topRevealTolerance: 1
        )

        _ = resolver.handle(offset: 0, minOffset: 0, canHide: false, canShow: false)
        _ = resolver.handle(offset: 16, minOffset: 0, canHide: true, canShow: true)

        XCTAssertEqual(resolver.reset(), .show)
        XCTAssertFalse(resolver.isHidden)
    }

    func testAutoHideEligibilityDisablesHideWhenContentHasNoDownwardRange() {
        let minOffset: CGFloat = 0
        let maxOffset = TabBarScrollAutoHideEligibility.maximumOffset(
            contentHeight: 420,
            viewportHeight: 600,
            adjustedInsets: .zero,
            minOffset: minOffset
        )

        XCTAssertEqual(maxOffset, 0)
        XCTAssertFalse(
            TabBarScrollAutoHideEligibility.canHide(
                offset: 12,
                minOffset: minOffset,
                maxOffset: maxOffset,
                isUserDriven: true
            )
        )
    }

    func testAutoHideEligibilityDisablesHideDuringBottomBounce() {
        let minOffset: CGFloat = 0
        let maxOffset = TabBarScrollAutoHideEligibility.maximumOffset(
            contentHeight: 1200,
            viewportHeight: 600,
            adjustedInsets: .zero,
            minOffset: minOffset
        )

        XCTAssertEqual(maxOffset, 600)
        XCTAssertFalse(
            TabBarScrollAutoHideEligibility.canHide(
                offset: 601,
                minOffset: minOffset,
                maxOffset: maxOffset,
                isUserDriven: true
            )
        )
        XCTAssertFalse(
            TabBarScrollAutoHideEligibility.canHide(
                offset: 598.5,
                minOffset: minOffset,
                maxOffset: maxOffset,
                isUserDriven: true
            )
        )
    }

    func testEdgeBounceEmitsOnceUntilScrollReturnsInBounds() {
        var resolver = TabBarScrollEdgeBounceResolver(overscrollThreshold: 8)

        XCTAssertFalse(
            resolver.handle(
                offset: 600,
                minOffset: 0,
                maxOffset: 600,
                isUserDragging: true
            )
        )
        XCTAssertTrue(
            resolver.handle(
                offset: 608,
                minOffset: 0,
                maxOffset: 600,
                isUserDragging: true
            )
        )
        XCTAssertFalse(
            resolver.handle(
                offset: 616,
                minOffset: 0,
                maxOffset: 600,
                isUserDragging: true
            )
        )

        XCTAssertFalse(
            resolver.handle(
                offset: 600,
                minOffset: 0,
                maxOffset: 600,
                isUserDragging: true
            )
        )
        XCTAssertTrue(
            resolver.handle(
                offset: 609,
                minOffset: 0,
                maxOffset: 600,
                isUserDragging: true
            )
        )
    }

    func testEdgeBounceRequiresActiveDragging() {
        var resolver = TabBarScrollEdgeBounceResolver(overscrollThreshold: 8)

        XCTAssertFalse(
            resolver.handle(
                offset: -12,
                minOffset: 0,
                maxOffset: 600,
                isUserDragging: false
            )
        )
        XCTAssertTrue(
            resolver.handle(
                offset: -12,
                minOffset: 0,
                maxOffset: 600,
                isUserDragging: true
            )
        )
    }
}
