//
//  ScrollPositionRestorer.swift
//  QuizFlash
//
//  Pixel-perfect scroll position save/restore across NavigationStack push/pop
//  transitions on iOS 17, using UIKit KVO on the underlying UIScrollView.
//
//  ─────────────────────────────────────────────────────────────────────────────
//  ROOT CAUSE — WHY THE PREVIOUS VERSION FAILED
//  ─────────────────────────────────────────────────────────────────────────────
//  The Library tab's UIScrollView is owned by the root UIHostingController in
//  the UINavigationController stack. When DeckView is pushed, that UIScrollView
//  is NOT removed from the window — it stays in the view hierarchy, obscured by
//  the incoming view controller's view.
//
//  Consequence: `didMoveToWindow` does NOT fire again on pop-back.
//
//  The previous version relied entirely on `didMoveToWindow` to arm restoration.
//  On pop-back, that callback was never called, so the restorer was silent. The
//  KVO contentOffset handler was active, but when SwiftUI's reconciliation pass
//  reset contentOffset to 0 (programmatically, without user interaction), the
//  handler dutifully saved that 0 into the ViewModel — corrupting the offset.
//  On the next appearance, `getOffset()` returned 0 and nothing was restored.
//
//  ─────────────────────────────────────────────────────────────────────────────
//  THE FIX — TWO-LAYER DEFENCE
//  ─────────────────────────────────────────────────────────────────────────────
//
//  Layer 1 — SwiftUI reset detection (KVO, always-on):
//    After the initial restoration cycle, the KVO contentOffset observer enters
//    live-save mode. Inside that handler, every offset change is tested against
//    a set of conditions that collectively identify a programmatic reset rather
//    than a user-initiated scroll:
//
//      • Large delta: |newY − oldY| > kResetDeltaThreshold (80pt)
//      • Near-zero landing: newY < kResetTopThreshold (10pt)
//      • Was meaningfully scrolled: lastKnownOffset > kResetDeltaThreshold
//      • No active touch: !isTracking && !isDragging && !isDecelerating
//
//    When all four conditions are met, the change is identified as SwiftUI's
//    post-pop reconciliation reset. `setContentOffset` is called asynchronously
//    (one run-loop pass) to override it without mutating contentOffset from
//    within its own KVO observation. `lastKnownOffset` is NOT updated,
//    preserving the true user position.
//
//  Layer 2 — `layoutSubviews` discovery fallback:
//    On some builds, `didMoveToWindow` fires before `superview` is fully
//    assembled by SwiftUI's hosting infrastructure. `layoutSubviews` is
//    guaranteed to run with a complete view hierarchy. If the UIScrollView
//    ancestor was not found in `didMoveToWindow`, `layoutSubviews` retries.
//
//  ─────────────────────────────────────────────────────────────────────────────
//  FOLDER VIEWS (pushed as NavigationDestination)
//  ─────────────────────────────────────────────────────────────────────────────
//  Folder LibraryViews are NEW view instances on each push. Their UIViews ARE
//  removed from the window on pop, so `didMoveToWindow(window: nil)` fires,
//  tearing down KVO. On the next push, `didMoveToWindow(window != nil)` fires
//  and re-arms restoration from the localViewModel's savedScrollOffset.
//  The two-layer defence is additive — it does not change folder view behaviour.
//
//  ─────────────────────────────────────────────────────────────────────────────
//  FEEDBACK-LOOP PREVENTION
//  ─────────────────────────────────────────────────────────────────────────────
//  `updateUIView` NEVER touches `hasRestored`, `targetOffset`, or
//  `lastKnownOffset`. Those properties are owned exclusively by `_ProbeView`
//  and are mutated only by UIKit lifecycle callbacks and KVO handlers.
//  This prevents:
//    • Live-scroll interruption: a SwiftUI re-render mid-scroll calling
//      setContentOffset() and killing momentum.
//    • KVO loop: setContentOffset → KVO → onOffsetChange → ViewModel update
//               → updateUIView → setContentOffset → ∞
//
//  ─────────────────────────────────────────────────────────────────────────────
//  USAGE
//  ─────────────────────────────────────────────────────────────────────────────
//  Place as the first child of the ScrollView's root VStack with a zero frame:
//
//      ScrollView {
//          VStack(spacing: 0) {
//              ScrollPositionRestorer(
//                  getOffset: { viewModel.savedScrollOffset },
//                  onOffsetChange: { offset in
//                      guard !isSearching else { return }
//                      viewModel.savedScrollOffset = offset
//                  }
//              )
//              .frame(width: 0, height: 0)
//              // ... rest of content ...
//          }
//      }
//

import SwiftUI

/// An explicit programmatic scroll command consumed by `ScrollPositionRestorer`.
///
/// This lets a feature request an intentional scroll change without being
/// misclassified as SwiftUI's unwanted contentOffset reset on iOS 17.
enum ScrollPositionRequestTarget: Equatable {
    case offset(CGFloat)
    case top
}

struct ScrollPositionRequest: Equatable {
    let id: Int
    let target: ScrollPositionRequestTarget
    let animated: Bool
}

struct ScrollPositionRestorer: UIViewRepresentable {

    // MARK: - Interface

    /// Returns the most recently persisted scroll offset.
    /// Read once per appearance cycle and once when re-arming after a tab switch.
    let getOffset: () -> CGFloat

    /// Invoked on every user-driven contentOffset change.
    /// Never called during restoration or when a SwiftUI reset is detected.
    let onOffsetChange: (CGFloat) -> Void

    /// Optional explicit programmatic scroll request.
    let scrollRequest: ScrollPositionRequest?

    init(
        getOffset: @escaping () -> CGFloat,
        onOffsetChange: @escaping (CGFloat) -> Void,
        scrollRequest: ScrollPositionRequest? = nil
    ) {
        self.getOffset = getOffset
        self.onOffsetChange = onOffsetChange
        self.scrollRequest = scrollRequest
    }

    // MARK: - Detection Thresholds

    /// Minimum vertical delta (pts) for a contentOffset change to be classified
    /// as a programmatic SwiftUI reset rather than user scrolling.
    private static let kResetDeltaThreshold: CGFloat = 80

    /// Maximum landing Y (pts) for a change to qualify as a reset to the top.
    /// Allows for fractional pixel offsets from SwiftUI's layout rounding.
    private static let kResetTopThreshold: CGFloat = 10

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> _ProbeView {
        _ProbeView(
            getOffset: getOffset,
            onOffsetChange: onOffsetChange,
            scrollRequest: scrollRequest,
            resetDelta: ScrollPositionRestorer.kResetDeltaThreshold,
            resetTop: ScrollPositionRestorer.kResetTopThreshold
        )
    }

    /// Only closures are refreshed here. Internal UIKit restoration state is
    /// intentionally never touched, preventing live-scroll interruption.
    func updateUIView(_ uiView: _ProbeView, context: Context) {
        uiView.getOffset = getOffset
        uiView.onOffsetChange = onOffsetChange
        uiView.applyScrollRequest(scrollRequest)
    }

    // MARK: - Probe View

    final class _ProbeView: UIView {

        // MARK: Interface (updated by updateUIView)

        var getOffset: () -> CGFloat
        var onOffsetChange: (CGFloat) -> Void
        private var latestScrollRequest: ScrollPositionRequest?

        // MARK: Configuration

        private let resetDelta: CGFloat
        private let resetTop: CGFloat

        // MARK: Internal State
        // All three properties are owned by this class and never mutated
        // from the SwiftUI side, guaranteeing feedback-loop safety.

        /// The offset to restore on the current appearance cycle.
        /// Set in `didMoveToWindow` (fresh appearance) or `attachToScrollView`
        /// (tab-switch return where scrollView was already attached).
        private var targetOffset: CGFloat = 0

        /// True after the initial scroll restoration has been committed.
        /// Gates live-save mode and the SwiftUI reset detector.
        private var hasRestored: Bool = false

        /// Last offset known to originate from the user or from our own restore.
        /// The reset detector uses this to distinguish a programmatic jump-to-zero
        /// from the user legitimately scrolling back to the top of the list.
        private var lastKnownOffset: CGFloat = 0

        // MARK: UIKit References

        private weak var scrollView: UIScrollView?
        private var offsetObservation: NSKeyValueObservation?
        private var contentSizeObservation: NSKeyValueObservation?
        private var activeProgrammaticScrollTarget: CGFloat?
        private var lastHandledScrollRequestID: Int?

        // MARK: Init

        init(
            getOffset: @escaping () -> CGFloat,
            onOffsetChange: @escaping (CGFloat) -> Void,
            scrollRequest: ScrollPositionRequest?,
            resetDelta: CGFloat,
            resetTop: CGFloat
        ) {
            self.getOffset = getOffset
            self.onOffsetChange = onOffsetChange
            self.latestScrollRequest = scrollRequest
            self.resetDelta = resetDelta
            self.resetTop = resetTop
            super.init(frame: .zero)
            isHidden = true
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("Not implemented") }

        // MARK: - UIKit Lifecycle

        /// Fires when the view enters a window.
        ///
        /// Covers two scenarios:
        ///   • Fresh first appearance (root tab on launch, folder view on push).
        ///   • Return from a tab switch, IF the tab's views were re-parented.
        ///
        /// Does NOT fire for the root Library tab on NavigationStack pop-back —
        /// that case is handled by the KVO-based SwiftUI reset detector.
        override func didMoveToWindow() {
            super.didMoveToWindow()

            if window != nil {
                targetOffset = getOffset()
                hasRestored = false

                if scrollView == nil {
                    // First appearance: discover the UIScrollView ancestor.
                    attachToScrollView()
                } else {
                    // Already attached (e.g. tab switch return). KVO is running.
                    // Re-arm the initial restoration pass.
                    attemptRestore()
                }
            } else {
                // View left the window (folder view popped, or app suspended).
                // Release UIKit references; next push re-discovers them.
                detachObservations()
            }
        }

        /// Backup discovery: runs with a complete superview chain, unlike
        /// `didMoveToWindow` which may fire while SwiftUI is still assembling
        /// the hosting view hierarchy.
        override func layoutSubviews() {
            super.layoutSubviews()
            guard window != nil, scrollView == nil else { return }
            attachToScrollView()
        }

        // MARK: - UIScrollView Discovery & KVO Setup

        private func attachToScrollView() {
            detachObservations()

            guard let sv = nearestScrollView() else { return }
            scrollView = sv
            lastKnownOffset = sv.contentOffset.y

            // ── ContentOffset Observer ───────────────────────────────────────────
            //
            // Operates in two sequential modes:
            //
            // MODE A — Restoration silent (hasRestored == false):
            //   Suppresses all saves. Any offset SwiftUI sets during initial layout
            //   must not corrupt lastKnownOffset before we have restored.
            //
            // MODE B — Live-save + reset detection (hasRestored == true):
            //   Saves user-driven offsets to the ViewModel. Detects SwiftUI's
            //   programmatic reset (post-pop reconciliation) and immediately
            //   overrides it, keeping the list at the user's true position.
            //
            offsetObservation = sv.observe(
                \.contentOffset,
                options: [.old, .new]
            ) { [weak self] scrollView, change in
                guard let self, self.hasRestored else { return }

                let newY = change.newValue?.y ?? 0
                let oldY = change.oldValue?.y ?? 0

                if let programmaticTarget = self.activeProgrammaticScrollTarget {
                    self.lastKnownOffset = newY
                    self.onOffsetChange(newY)

                    if abs(newY - programmaticTarget) <= 1 {
                        self.activeProgrammaticScrollTarget = nil
                    }
                    return
                }

                // SwiftUI post-pop reconciliation produces a large, instantaneous
                // jump to zero with zero user-touch indicators. Detect and override.
                let isSuddenProgrammaticReset =
                    abs(newY - oldY) > self.resetDelta   // large delta
                    && newY < self.resetTop               // landing near the very top
                    && self.lastKnownOffset > self.resetDelta  // was meaningfully scrolled
                    && !scrollView.isTracking             // no active touch
                    && !scrollView.isDragging
                    && !scrollView.isDecelerating

                if isSuddenProgrammaticReset {
                    // Override asynchronously: mutating contentOffset synchronously
                    // from within a KVO observation of contentOffset is undefined.
                    let restore = self.lastKnownOffset
                    DispatchQueue.main.async { [weak scrollView] in
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        UIView.performWithoutAnimation {
                            scrollView?.setContentOffset(CGPoint(x: 0, y: restore), animated: false)
                        }
                        CATransaction.commit()
                    }
                    // lastKnownOffset intentionally NOT updated — the true user
                    // position is `restore`, not the 0 SwiftUI wrote.
                    return
                }

                // Normal user-driven scroll: update local cache and persist.
                self.lastKnownOffset = newY
                self.onOffsetChange(newY)
            }

            // ── ContentSize Observer ─────────────────────────────────────────────
            // LazyVStack materializes cells incrementally as the viewport advances.
            // contentSize grows with each batch of newly rendered cells. Restoration
            // cannot proceed until contentSize is tall enough to reach targetOffset,
            // so we observe and retry on every growth event.
            contentSizeObservation = sv.observe(\.contentSize, options: .new) { [weak self] _, _ in
                self?.attemptRestore()
            }

            // Attempt immediately — contentSize may already be sufficient.
            attemptRestore()
            applyScrollRequestIfNeeded()
        }

        // MARK: - Initial Restoration

        /// Commits scroll restoration if the content is tall enough to reach
        /// `targetOffset`. Called on every contentSize change and once immediately
        /// after `attachToScrollView`. Idempotent via `hasRestored`.
        private func attemptRestore() {
            guard !hasRestored else { return }

            // No UIKit call needed for offset 0 — just enable live-save immediately.
            guard targetOffset > 0 else {
                hasRestored = true
                lastKnownOffset = 0
                return
            }

            guard let sv = scrollView else { return }

            // Wait until LazyVStack has enough content to actually reach targetOffset.
            let maxScrollable = sv.contentSize.height
                - sv.bounds.height
                + sv.adjustedContentInset.bottom
            guard maxScrollable >= targetOffset else { return }

            // Synchronous, non-animated. Double-wrapped to survive any active
            // UIKit animation transaction (e.g. tab switch animation context):
            //   • CATransaction.setDisableActions — stops Core Animation from
            //     interpolating the layer position change.
            //   • UIView.performWithoutAnimation — stops UIKit's implicit
            //     UIView animation block from picking up the offset change.
            // Without both wrappers, setContentOffset called during a tab switch
            // is interpolated by the tab animation and the list visibly slides.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                sv.setContentOffset(CGPoint(x: 0, y: targetOffset), animated: false)
            }
            CATransaction.commit()

            lastKnownOffset = targetOffset
            hasRestored = true
        }

        // MARK: - Helpers

        /// Walks the superview chain to find the nearest UIScrollView ancestor.
        /// SwiftUI renders ScrollView content inside a _UIHostingView that is a
        /// direct child of the UIScrollView, so this walk reliably finds the target
        /// through any number of intermediate SwiftUI layout UIView wrappers.
        private func nearestScrollView() -> UIScrollView? {
            var candidate: UIView? = superview
            while let view = candidate {
                if let sv = view as? UIScrollView { return sv }
                candidate = view.superview
            }
            return nil
        }

        private func detachObservations() {
            offsetObservation?.invalidate()
            offsetObservation = nil
            contentSizeObservation?.invalidate()
            contentSizeObservation = nil
            scrollView = nil
        }

        func applyScrollRequest(_ request: ScrollPositionRequest?) {
            latestScrollRequest = request
            applyScrollRequestIfNeeded()
        }

        private func applyScrollRequestIfNeeded() {
            guard let request = latestScrollRequest else { return }
            guard lastHandledScrollRequestID != request.id else { return }
            guard let scrollView else { return }

            let resolvedTarget = resolveTargetOffset(for: request.target, in: scrollView)

            lastHandledScrollRequestID = request.id
            activeProgrammaticScrollTarget = resolvedTarget
            targetOffset = resolvedTarget
            hasRestored = true
            lastKnownOffset = resolvedTarget

            if request.animated {
                scrollView.setContentOffset(
                    CGPoint(x: 0, y: resolvedTarget),
                    animated: true
                )
            } else {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                UIView.performWithoutAnimation {
                    scrollView.setContentOffset(
                        CGPoint(x: 0, y: resolvedTarget),
                        animated: false
                    )
                }
                CATransaction.commit()
                onOffsetChange(resolvedTarget)
                activeProgrammaticScrollTarget = nil
            }
        }

        private func resolveTargetOffset(
            for target: ScrollPositionRequestTarget,
            in scrollView: UIScrollView
        ) -> CGFloat {
            switch target {
            case .offset(let rawOffset):
                return rawOffset
            case .top:
                return -scrollView.adjustedContentInset.top
            }
        }

        deinit { detachObservations() }
    }
}
