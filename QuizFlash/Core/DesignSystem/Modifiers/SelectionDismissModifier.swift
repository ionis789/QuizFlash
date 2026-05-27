//
//  SelectionDismissModifier.swift
//  QuizFlash
//
//  A zero-size UIViewRepresentable placed in .background installs a
//  UITapGestureRecognizer directly on the UIWindow. The SwiftUI view itself
//  has zero frame and allowsHitTesting(false) so it never intercepts touches.
//  The window-level recognizer fires independently of SwiftUI hit-testing.
//

import SwiftUI


// MARK: - WindowTapInstaller

struct WindowTapInstaller: UIViewRepresentable {

    var isActive: Bool
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let v = PassthroughView()
        v.coordinator = context.coordinator
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.onTap   = onTap
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isActive = false
        var onTap: () -> Void = {}
        private weak var tap: UITapGestureRecognizer?

        func install(on window: UIWindow) {
            guard tap == nil else { return }
            let gr = UITapGestureRecognizer(target: self, action: #selector(fired(_:)))
            gr.delegate = self
            gr.cancelsTouchesInView = false   // never steal touches
            gr.delaysTouchesBegan   = false
            gr.delaysTouchesEnded   = false
            window.addGestureRecognizer(gr)
            tap = gr
        }

        func uninstall() {
            if let gr = tap { gr.view?.removeGestureRecognizer(gr) }
            tap = nil
        }

        @objc private func fired(_ gr: UITapGestureRecognizer) {
            guard isActive, let window = gr.view as? UIWindow else { return }
            let pt = gr.location(in: window)
            guard !hitsInteractiveView(at: pt, in: window) else { return }
            onTap()
        }

        // Walk the hit-test chain; bail only if a UIControl or another
        // UITapGestureRecognizer (i.e. a tappable SwiftUI element) is found.
        // Pan/scroll recognizers on hosting views are intentionally ignored so
        // that tapping empty space in the scroll area still triggers dismiss.
        private func hitsInteractiveView(at pt: CGPoint, in window: UIWindow) -> Bool {
            var v = window.hitTest(pt, with: nil)
            while let view = v {
                if view is UIControl { return true }
                let hasTap = view.gestureRecognizers?.contains {
                    $0 is UITapGestureRecognizer && $0 !== tap
                } ?? false
                if hasTap { return true }
                v = view.superview
            }
            return false
        }

        // Co-exist with every other recognizer — never steal the touch.
        func gestureRecognizer(_ gr: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ gr: UIGestureRecognizer,
                               shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }
        func gestureRecognizer(_ gr: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
    }

    // MARK: PassthroughView

    final class PassthroughView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let w = window { coordinator?.install(on: w) }
            else              { coordinator?.uninstall() }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Installs a window-level tap recognizer. The recognizer co-exists with
    /// all SwiftUI gestures — interactive views (deck rows, buttons) are
    /// detected via hitTest and excluded from the dismiss action.
    func onWindowTap(isActive: Bool, perform action: @escaping () -> Void) -> some View {
        // .background with zero frame — never participates in hit-testing.
        self.background(
            WindowTapInstaller(isActive: isActive, onTap: action)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}
