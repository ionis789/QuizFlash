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
//    • hitView is UIScrollView              → bare surface    → dismiss ✓
//    • hitView is PlatformGroupContainer    → empty space     → dismiss ✓
//    • hitView is anything else             → leaf content    → block   ✗
//
//  ⚠️  Container detection is deliberately conservative: only PlatformGroupContainer
//  is allowlisted. Broad prefix checks like `_SwiftUI` or `_UIHostingView` are
//  intentionally absent — they are fragile against deck row refactors that introduce
//  SwiftUI-bridged subviews whose class names match those prefixes.
//
//  If empty-space detection stops working after a UI refactor, enable the
//  SVEST_DEBUG flag (target → Build Settings → OTHER_SWIFT_FLAGS → -DSVEST_DEBUG)
//  and check the Xcode console output to identify the new container class name.
//

import SwiftUI
import UIKit
import OSLog

// MARK: - ScrollViewEmptySpaceTap

struct ScrollViewEmptySpaceTap: UIViewRepresentable {
    private static let logger = QuizFlashLog.make("ScrollViewEmptySpaceTap")

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

        /// Returns `true` when the tap lands on genuinely empty scroll-view space
        /// with no deck row or other interactive content at the tapped pixel.
        ///
        /// Detection strategy — two independent signals:
        ///
        /// 1. **`PlatformGroupContainer` as deepest hit view.**
        ///    When no deck card covers the tapped pixel, UIKit stops at
        ///    `PlatformGroupContainer` (the SwiftUI host for the entire LazyVStack).
        ///    When a deck card does cover the pixel, UIKit descends into a leaf
        ///    view inside the card. Container-as-deepest = definitive empty signal.
        ///
        /// 2. **`hitView === scrollView` ONLY when no content subview exists at
        ///    the point (verified via `contentView` walk).**
        ///    Returning `true` unconditionally for `hitView === scrollView` is
        ///    unsafe: a broken `_UIReparentingView` hierarchy (caused by a
        ///    `.contextMenu` with `preview:` on deck rows) makes `hitTest` fall
        ///    back to the scroll view even for deck card taps, producing a false
        ///    positive. The extra `hasNoContentSubview` guard prevents this.
        ///
        /// **Explicit blocklist for UIKit reparenting artifacts.**
        /// `_UIReparentingView` is added to the deck row hierarchy by UIKit's
        /// context-menu interaction when a `preview:` block is present. If it
        /// appears as the deepest hit view, the tap is on a deck row — never
        /// on empty space — and the gesture must not begin.
        private func isEmptySpace(at point: CGPoint, in scrollView: UIScrollView) -> Bool {
            guard let hitView = scrollView.hitTest(point, with: nil) else {
                // Point is outside the scroll view bounds entirely.
                return true
            }

            #if SVEST_DEBUG
            // Enable with OTHER_SWIFT_FLAGS = -DSVEST_DEBUG in Build Settings.
            // Tap on a deck card  → should print a leaf class (RBDrawingView, etc.)
            // Tap on empty space  → should print PlatformGroupContainer
            let className = String(describing: type(of: hitView))
            ScrollViewEmptySpaceTap.logger.debug(
                "[SVEST] hitTest: \(className, privacy: .public) | isContainer: \(self.isKnownEmptySpaceView(hitView)) | isBlocked: \(self.isReparentingArtifact(hitView))"
            )
            #endif

            // UIKit reparenting artifacts appear inside deck rows when a
            // .contextMenu with preview: is installed. They are never empty space.
            if isReparentingArtifact(hitView) { return false }

            // Bare scroll-view surface, but ONLY if no content subview exists at
            // this point. The extra check guards against broken _UIReparentingView
            // hierarchies where hitTest falls back to the scrollView for card taps.
            if hitView === scrollView {
                return hasNoContentSubview(at: point, in: scrollView)
            }

            // SwiftUI layout container as deepest view — no card covers this pixel.
            if isKnownEmptySpaceView(hitView) { return true }

            // Leaf content view — tap is on a deck row or other interactive element.
            return false
        }

        /// Returns `true` only for SwiftUI layout container classes that span
        /// large content areas but contain no interactive pixels of their own.
        /// Deliberately narrow — broad prefix checks were removed to prevent
        /// false positives from UIHostingView-wrapped deck subviews.
        private func isKnownEmptySpaceView(_ view: UIView) -> Bool {
            let name = String(describing: type(of: view))
            // Primary SwiftUI content host for LazyVStack — confirmed via debug.
            if name == "PlatformGroupContainer" { return true }
            // ─────────────────────────────────────────────────────────────────
            // Intentionally absent:
            //   _UIHostingView prefix — matches UIHostingView-wrapped deck subviews.
            //   _SwiftUI prefix       — matches rendering leaves inside deck cards.
            // ─────────────────────────────────────────────────────────────────
            return false
        }

        /// Returns `true` for UIKit-internal views injected by context-menu
        /// interaction machinery. These always live inside deck rows, never on
        /// empty space, and must never trigger the dismiss gesture.
        ///
        /// `_UIReparentingView` is inserted when `.contextMenu(preview:)` is
        /// active on a deck row. If the reparenting fails (logged as a warning),
        /// the view may remain in the hierarchy and become the deepest hit view
        /// for subsequent taps on the affected row.
        private func isReparentingArtifact(_ view: UIView) -> Bool {
            let name = String(describing: type(of: view))
            if name == "_UIReparentingView"             { return true }
            if name == "_UIContextMenuContainerView"    { return true }
            if name == "_UIContextMenuActionsListView"  { return true }
            return false
        }

        /// Confirms that no content subview of `scrollView` covers `point`.
        /// Used as a secondary guard when `hitTest` returns the scroll view itself
        /// — a situation that can occur both legitimately (bare surface below all
        /// content) and erroneously (broken `_UIReparentingView` hierarchy).
        private func hasNoContentSubview(at point: CGPoint, in scrollView: UIScrollView) -> Bool {
            for subview in scrollView.subviews {
                // Skip the scroll indicators and other UIScrollView internals.
                let subName = String(describing: type(of: subview))
                if subName.hasPrefix("_UIScrollView") { continue }
                if subName.hasPrefix("UIImageView")   { continue }  // scroll indicator
                let convertedPoint = scrollView.convert(point, to: subview)
                if subview.bounds.contains(convertedPoint) {
                    // A content subview covers this point — not bare surface.
                    return false
                }
            }
            return true
        }
    }

    // MARK: - AnchorView

    /// Zero-size UIView that locates the ancestor UIScrollView and installs the
    /// tap recognizer once the full UIKit hierarchy is assembled.
    ///
    /// Uses `didMoveToWindow` (not `didMoveToSuperview`) because SwiftUI builds the
    /// UIKit hierarchy inside-out. At `didMoveToSuperview` time the UIScrollView
    /// ancestor is not yet attached above AnchorView in the chain.
    /// `didMoveToWindow` fires after the complete hierarchy is connected to the
    /// window. A main-actor task yield defers by one run-loop cycle to let
    /// SwiftUI finish any pending layout pass before we walk the superview chain.
    final class AnchorView: UIView {

        weak var coordinator: Coordinator?
        private var attachmentTask: Task<Void, Never>?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachmentTask?.cancel()
            guard window != nil else {
                coordinator?.detach()
                return
            }

            attachmentTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.window != nil else { return }
                if let sv = self.nearestAncestorScrollView() {
                    self.coordinator?.attach(to: sv)
                }
            }
        }

        deinit {
            attachmentTask?.cancel()
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
    /// scroll-view surface or `PlatformGroupContainer` with no child content at
    /// the tapped pixel (gaps between deck rows, area below all decks).
    ///
    /// Deck rows and any other leaf SwiftUI content are excluded automatically.
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
