//
//  ScrollViewEmptySpaceTap.swift
//  QuizFlash
//
//  Abstract:
//  Detects taps on genuinely empty space inside the nearest ancestor UIScrollView
//  without interfering with deck rows or any other SwiftUI-rendered content.
//
//  How empty space is identified (derived from debug logging):
//
//  PlatformGroupContainer is the single UIView that SwiftUI uses to host the
//  entire LazyVStack content tree. Its frame spans the full scroll content height
//  (e.g. 1797 pt for 13 decks). It is always present in the hierarchy.
//
//  The critical observation from hitTest behaviour:
//
//    Tap on a deck card  → hitTest returns a LEAF view (RBDrawingView, UILabel…)
//                          that lives *inside* PlatformGroupContainer.
//                          The card's child views claimed the touch first.
//
//    Tap on empty space  → hitTest returns PlatformGroupContainer *itself* as the
//                          deepest view. No child view covers that pixel, so UIKit
//                          stops at the container.
//
//    Tap below all decks → same as above; PlatformGroupContainer is deepest.
//
//  Decision rule — check hitView identity only, no walk needed:
//    • hitView is UIScrollView                  → bare surface    → dismiss ✓
//    • hitView IS a SwiftUI container class     → empty space     → dismiss ✓
//      (PlatformGroupContainer, _UIHostingView…)
//    • hitView is anything else                 → leaf content    → block   ✗
//      (RBDrawingView, UILabel, _UIInheritedView… inside a deck row)
//

import SwiftUI
import UIKit

// MARK: - ScrollViewEmptySpaceTap

struct ScrollViewEmptySpaceTap: UIViewRepresentable {

    /// When `false` the recognizer never begins, leaving all touch handling untouched.
    var isActive: Bool

    /// Called on the main thread when a tap on genuinely empty space is confirmed.
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.onTap   = onTap
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var isActive: Bool    = false
        var onTap: () -> Void = {}

        private weak var attachedScrollView: UIScrollView?
        private weak var tapRecognizer: UITapGestureRecognizer?

        // MARK: Attachment

        func attach(to scrollView: UIScrollView) {
            guard attachedScrollView !== scrollView else { return }
            detach()

            let gr = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            // Never steal touches from deck rows or any other child view.
            gr.cancelsTouchesInView = false
            gr.delaysTouchesBegan   = false
            gr.delaysTouchesEnded   = false
            gr.delegate             = self
            scrollView.addGestureRecognizer(gr)

            attachedScrollView = scrollView
            tapRecognizer      = gr
        }

        func detach() {
            if let gr = tapRecognizer { gr.view?.removeGestureRecognizer(gr) }
            tapRecognizer      = nil
            attachedScrollView = nil
        }

        @objc private func handleTap() {
            onTap()
        }

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isActive,
                  gestureRecognizer === tapRecognizer,
                  let scrollView = attachedScrollView
            else { return false }

            let point = gestureRecognizer.location(in: scrollView)
            return isEmptySpace(at: point, in: scrollView)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        // MARK: - Empty-Space Detection

        /// Returns `true` when the tap lands on bare scroll-view surface or on a
        /// SwiftUI layout container with no child content at that pixel.
        ///
        /// The check is intentionally shallow — we only inspect the single deepest
        /// view returned by hitTest, not the full superview chain.
        ///
        /// Rationale:
        /// PlatformGroupContainer spans the full LazyVStack height. When the user
        /// taps on a deck card, a leaf view (RBDrawingView) inside the container
        /// captures the hit and becomes the deepest view. When the tap lands on
        /// empty space (gaps between cards, area below all cards), no leaf view
        /// covers that pixel and UIKit returns the container itself as deepest.
        /// Container-as-deepest-view is therefore the definitive empty-space signal.
        private func isEmptySpace(at point: CGPoint, in scrollView: UIScrollView) -> Bool {
            guard let hitView = scrollView.hitTest(point, with: nil) else {
                // Point is outside the scroll view bounds entirely.
                return true
            }

            // Tap landed on the bare UIScrollView surface — no content layer at all.
            if hitView === scrollView { return true }

            // Tap landed on a SwiftUI layout container acting as the deepest view.
            // This means no child view (deck card, label, button) covers this pixel.
            // The container caught the tap only because it fills the content area —
            // the pixel itself is visually and interactively empty.
            if isSwiftUILayoutContainer(hitView) { return true }

            // Tap landed on a real content leaf view (RBDrawingView, UILabel, etc.)
            // that lives inside a deck row — do not dismiss.
            return false
        }

        /// Returns `true` for UIView subclasses that SwiftUI uses as layout
        /// containers rather than as content-rendering leaves.
        ///
        /// These views fill large areas of the scroll content but contain no
        /// user-visible interactive pixels of their own — they are transparent
        /// pass-through containers. When hitTest returns one of these as the
        /// *deepest* hit view, it means no actual content lives at that point.
        private func isSwiftUILayoutContainer(_ view: UIView) -> Bool {
            let name = String(describing: type(of: view))
            // SwiftUI's primary content hosting container (wraps LazyVStack et al).
            // Confirmed as the deepest hit view for all empty-space taps via debug.
            if name == "PlatformGroupContainer" { return true }
            // UIHostingView subclasses — root SwiftUI-to-UIKit bridges.
            if name.hasPrefix("_UIHostingView")  { return true }
            // Any other SwiftUI-private container view.
            if name.hasPrefix("_SwiftUI")         { return true }
            return false
        }
    }

    // MARK: - AnchorView

    /// Zero-size UIView that locates the ancestor UIScrollView and installs the
    /// tap recognizer once the full UIKit hierarchy is assembled.
    ///
    /// Uses didMoveToWindow (not didMoveToSuperview) because SwiftUI builds the
    /// UIKit hierarchy inside-out. At didMoveToSuperview time the UIScrollView
    /// ancestor is not yet attached above AnchorView in the chain.
    /// didMoveToWindow fires after the complete hierarchy is connected to the
    /// window. DispatchQueue.main.async defers by one run-loop cycle to let
    /// SwiftUI finish any pending layout pass before we walk the superview chain.
    final class AnchorView: UIView {

        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                coordinator?.detach()
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                if let sv = self.nearestAncestorScrollView() {
                    self.coordinator?.attach(to: sv)
                }
            }
        }

        private func nearestAncestorScrollView() -> UIScrollView? {
            var v: UIView? = superview
            while let view = v {
                if let sv = view as? UIScrollView { return sv }
                v = view.superview
            }
            return nil
        }
    }
}

// MARK: - View Extension

extension View {

    /// Installs an empty-space tap handler on the nearest ancestor UIScrollView.
    ///
    /// `action` fires only when `isActive` is `true` AND the tap lands on bare
    /// scroll-view surface or a SwiftUI layout container with no child content
    /// at the tapped pixel (gaps between deck rows, area below all decks).
    ///
    /// Deck rows and any other leaf SwiftUI content are excluded automatically —
    /// no additional configuration required.
    func onScrollViewEmptySpaceTap(
        isActive: Bool,
        perform action: @escaping () -> Void
    ) -> some View {
        background(
            ScrollViewEmptySpaceTap(isActive: isActive, onTap: action)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}
