//
//  KeyboardDismissOnBackgroundTapModifier.swift
//  QuizFlash
//

import SwiftUI
import UIKit

extension View {
    /// Dismisses the software keyboard when the user taps a non-interactive region.
    ///
    /// The recognizer is attached in UIKit so it can distinguish between
    /// background taps and controls embedded deep inside composed SwiftUI layouts.
    func dismissKeyboardOnBackgroundTap(enabled: Bool = true) -> some View {
        modifier(KeyboardDismissModifier(enabled: enabled))
    }
}

private struct KeyboardDismissModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        content.background(
            KeyboardDismissTapController(enabled: enabled)
        )
    }
}

private struct KeyboardDismissTapController: UIViewRepresentable {
    let enabled: Bool

    func makeUIView(context: Context) -> KeyboardDismissControllerView {
        let view = KeyboardDismissControllerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: KeyboardDismissControllerView, context: Context) {
        context.coordinator.parent = self
        uiView.coordinator = context.coordinator
        uiView.refreshGestureAttachmentIfNeeded()
        uiView.tapRecognizer?.isEnabled = enabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: KeyboardDismissTapController

        init(parent: KeyboardDismissTapController) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard parent.enabled else { return }
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard parent.enabled else { return false }
            return isBackgroundTouch(touch.view)
        }

        private func isBackgroundTouch(_ touchedView: UIView?) -> Bool {
            var current = touchedView

            while let view = current {
                if view is UITextField || view is UITextView || view is UISearchBar || view is UIControl {
                    return false
                }

                if view is UITableViewCell || view is UICollectionViewCell {
                    return false
                }

                current = view.superview
            }

            return true
        }
    }
}

private final class KeyboardDismissControllerView: UIView {
    weak var coordinator: KeyboardDismissTapController.Coordinator?
    private weak var gestureHostView: UIView?
    private var tapGesture: UITapGestureRecognizer?

    var tapRecognizer: UITapGestureRecognizer? { tapGesture }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshGestureAttachmentIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshGestureAttachmentIfNeeded()
    }

    func refreshGestureAttachmentIfNeeded() {
        guard let coordinator, let target = window else {
            detachGesture()
            return
        }

        if tapGesture == nil {
            let tap = UITapGestureRecognizer(
                target: coordinator,
                action: #selector(KeyboardDismissTapController.Coordinator.handleTap(_:))
            )
            tap.delegate = coordinator
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tapGesture = tap
        }

        guard let tapGesture else { return }
        if gestureHostView !== target {
            detachGesture()
            target.addGestureRecognizer(tapGesture)
            gestureHostView = target
        }
    }

    private func detachGesture() {
        if let tapGesture {
            tapGesture.view?.removeGestureRecognizer(tapGesture)
        }
        gestureHostView = nil
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil {
            detachGesture()
            tapGesture = nil
        }
        super.willMove(toWindow: newWindow)
    }
}
