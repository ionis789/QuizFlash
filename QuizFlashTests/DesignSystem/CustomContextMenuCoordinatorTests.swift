//
//  CustomContextMenuCoordinatorTests.swift
//  QuizFlashTests
//
//  Covers dismiss sequencing for the shared custom context-menu coordinator.
//

import SwiftUI
import XCTest
@testable import QuizFlash

@MainActor
final class CustomContextMenuCoordinatorTests: XCTestCase {
    func testDismissClearsPresentationAndResetsPhase() async {
        let coordinator = CustomContextMenuCoordinator()
        coordinator.presentation = makePresentation(sourceID: "dismiss-source")
        coordinator.phase = .expanded

        coordinator.dismiss()

        XCTAssertEqual(coordinator.phase, .dismissing)
        XCTAssertTrue(coordinator.isSourceHidden("dismiss-source"))

        try? await Task.sleep(for: .milliseconds(260))

        XCTAssertNil(coordinator.presentation)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertFalse(coordinator.isSourceHidden("dismiss-source"))
    }

    func testPerformActionExecutesAfterDismissCompletes() async {
        let coordinator = CustomContextMenuCoordinator()
        coordinator.presentation = makePresentation(sourceID: "action-source")
        coordinator.phase = .expanded

        var didRunAction = false
        coordinator.performAction {
            didRunAction = true
        }

        XCTAssertFalse(didRunAction)
        XCTAssertEqual(coordinator.phase, .dismissing)

        try? await Task.sleep(for: .milliseconds(260))

        XCTAssertNil(coordinator.presentation)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(didRunAction)
    }

    private func makePresentation(sourceID: String) -> CustomContextMenuCoordinator.Presentation {
        let layout = CustomContextMenuLayoutResolver.resolveLayout(
            sourceFrame: CGRect(x: 160, y: 220, width: 120, height: 80),
            measuredMenuSize: CGSize(width: 200, height: 180),
            config: CustomContextMenuConfig(),
            windowBounds: CGRect(x: 0, y: 0, width: 390, height: 844),
            safeInsets: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        )

        return CustomContextMenuCoordinator.Presentation(
            sourceID: sourceID,
            sourceFrame: CGRect(x: 160, y: 220, width: 120, height: 80),
            preview: AnyView(Color.clear.frame(width: 120, height: 80)),
            infoRows: [.init(label: "Type", value: "Flash")],
            actions: [
                CustomContextMenuAction(
                    title: "Edit",
                    systemImage: "pencil",
                    role: .normal,
                    action: { }
                )
            ],
            menuSize: CGSize(width: 200, height: 180),
            config: CustomContextMenuConfig(),
            layout: layout
        )
    }
}
