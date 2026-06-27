//
//  TabBarScrollAutoHideResolverTests.swift
//  QuizFlashTests
//
//  Guards the floating tab bar's scroll-driven compacting behavior.
//

import XCTest
@testable import QuizFlash

final class TabBarScrollAutoHideResolverTests: XCTestCase {
    func testBottomOverscrollDrivesContinuousProgress() {
        var resolver = TabBarScrollCompactProgressResolver(compactDistance: 40, changeEpsilon: 0)

        assertProgress(
            resolver.handle(
                offset: 610,
                minOffset: 0,
                maxOffset: 600,
                isUserDriven: true,
                isDragging: true
            ),
            equals: 0.25,
            animated: false
        )

        assertProgress(
            resolver.handle(
                offset: 640,
                minOffset: 0,
                maxOffset: 600,
                isUserDriven: true,
                isDragging: true
            ),
            equals: 1,
            animated: false
        )
    }

    func testTopOverscrollDoesNotCompact() {
        var resolver = TabBarScrollCompactProgressResolver(compactDistance: 40, changeEpsilon: 0)

        XCTAssertNil(
            resolver.handle(
                offset: -20,
                minOffset: 0,
                maxOffset: 600,
                isUserDriven: true,
                isDragging: true
            )
        )
        XCTAssertEqual(resolver.progress, 0)
    }

    func testInBoundsScrollDoesNotCompactBeforeBottom() {
        var resolver = TabBarScrollCompactProgressResolver(compactDistance: 40, changeEpsilon: 0)

        XCTAssertNil(
            resolver.handle(
                offset: 420,
                minOffset: 0,
                maxOffset: 600,
                isUserDriven: true,
                isDragging: true
            )
        )
        XCTAssertEqual(resolver.progress, 0)
    }

    func testReleaseResetsProgressWithAnimation() {
        var resolver = TabBarScrollCompactProgressResolver(compactDistance: 40, changeEpsilon: 0)

        _ = resolver.handle(
            offset: 620,
            minOffset: 0,
            maxOffset: 600,
            isUserDriven: true,
            isDragging: true
        )
        XCTAssertEqual(resolver.progress, 0.5)

        assertProgress(
            resolver.handle(
                offset: 620,
                minOffset: 0,
                maxOffset: 600,
                isUserDriven: true,
                isDragging: false
            ),
            equals: 0,
            animated: true
        )
    }

    func testResetEmitsOnlyWhenProgressWasActive() {
        var resolver = TabBarScrollCompactProgressResolver(compactDistance: 40, changeEpsilon: 0)

        XCTAssertNil(resolver.reset())

        _ = resolver.handle(
            offset: 620,
            minOffset: 0,
            maxOffset: 600,
            isUserDriven: true,
            isDragging: true
        )

        assertProgress(resolver.reset(), equals: 0, animated: true)
    }

    func testCompactEligibilityDisablesProgressWhenContentHasNoVerticalRange() {
        let minOffset: CGFloat = 0
        let maxOffset = TabBarScrollAutoHideEligibility.maximumOffset(
            contentHeight: 420,
            viewportHeight: 600,
            adjustedInsets: .zero,
            minOffset: minOffset
        )
        var resolver = TabBarScrollCompactProgressResolver(compactDistance: 40, changeEpsilon: 0)

        XCTAssertEqual(maxOffset, 0)
        XCTAssertNil(
            resolver.handle(
                offset: 20,
                minOffset: minOffset,
                maxOffset: maxOffset,
                isUserDriven: true,
                isDragging: true
            )
        )
        XCTAssertEqual(resolver.progress, 0)
    }

    func testMaximumOffsetIncludesBottomInset() {
        let maxOffset = TabBarScrollAutoHideEligibility.maximumOffset(
            contentHeight: 1200,
            viewportHeight: 600,
            adjustedInsets: UIEdgeInsets(top: 0, left: 0, bottom: 40, right: 0),
            minOffset: 0
        )

        XCTAssertEqual(maxOffset, 640)
    }

    private func assertProgress(
        _ action: TabBarAutoHideAction?,
        equals expectedProgress: CGFloat,
        animated expectedAnimated: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .setCompactProgress(progress, animated) = action else {
            XCTFail("Expected compact progress action", file: file, line: line)
            return
        }

        XCTAssertEqual(progress, expectedProgress, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(animated, expectedAnimated, file: file, line: line)
    }
}
