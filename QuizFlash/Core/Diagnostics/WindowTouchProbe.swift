//
//  WindowTouchProbe.swift
//  QuizFlash
//
//  Development-only touch delivery probe.
//

#if DEBUG
import OSLog
import SwiftUI
import UIKit

// MARK: - WindowTouchProbe

struct WindowTouchProbe: UIViewRepresentable {

    private static let isEnabled = ProcessInfo.processInfo.environment["QUIZFLASH_TOUCH_PROBE"] == "1"

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = PassthroughView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(isEnabled: Self.isEnabled)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled = false
        private var didReportActivation = false
        private weak var recognizer: UITapGestureRecognizer?
        private let logger = QuizFlashLog.make("WindowTouchProbe")

        func update(isEnabled: Bool) {
            self.isEnabled = isEnabled
            guard isEnabled, !didReportActivation else { return }
            didReportActivation = true
            logger.notice("active")
        }

        func install(on window: UIWindow) {
            guard recognizer == nil else { return }

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer

            if isEnabled {
                logger.notice("installed window=\(String(describing: window), privacy: .public)")
            }
        }

        func uninstall() {
            if let recognizer {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard isEnabled, let window = recognizer.view as? UIWindow else { return }

            let point = recognizer.location(in: window)
            let hitView = window.hitTest(point, with: nil)
            let hitType = hitView.map { String(describing: type(of: $0)) } ?? "nil"
            let state = String(describing: recognizer.state)
            logger.notice(
                "tap state=\(state, privacy: .public) point=(\(point.x, privacy: .public), \(point.y, privacy: .public)) hit=\(hitType, privacy: .public)"
            )
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }

    // MARK: - PassthroughView

    final class PassthroughView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window {
                coordinator?.install(on: window)
            } else {
                coordinator?.uninstall()
            }
        }
    }
}

// MARK: - View Extension

extension View {
    func windowTouchProbe() -> some View {
        background(
            WindowTouchProbe()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}
#endif
