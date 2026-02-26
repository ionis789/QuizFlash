//
//  ScrollOffsetReader.swift
//  QuizFlash
//
//  Fixed: Eliminated memory leak from Binding<CGFloat> storage +
//         DispatchQueue.main.async accumulation storm.
//
//  Use this ONLY as an iOS 17 fallback.
//  On iOS 18+ prefer .onScrollGeometryChange in DeckView via ScrollCollapseTracker.
//

import SwiftUI
import UIKit

// MARK: - ScrollOffsetReader (iOS 17 Fallback)

/// Bridges UIScrollView's contentOffset into a SwiftUI @MainActor callback.
///
/// ── Original memory leak: 3 causes in a feedback loop ──────────────────────
///
/// 1. `Binding<CGFloat>` stored in Coordinator
///    A SwiftUI Binding wraps the @Observable registrar. Holding it off-heap in
///    a UIKit Coordinator created a reference path that prevented the observation
///    graph from being released frame-to-frame. Each new Binding copy (created on
///    every updateUIView call) added another entry to the registrar table.
///
/// 2. `DispatchQueue.main.async` on every updateUIView call
///    updateUIView fires every time `collapseProgress` changes (≤120×/sec). Each
///    call dispatched a new async block onto the main queue. At 120 Hz the blocks
///    queued faster than they drained — thousands of closures, each holding a
///    strong Binding reference. That was your +5 MB/scroll-gesture symptom.
///
/// 3. Feedback loop
///    Writing to the Binding in the async block triggered a SwiftUI re-render
///    → another updateUIView → another async dispatch → repeat ∞.
///
/// ── Fix ────────────────────────────────────────────────────────────────────
///
/// Two changes, working together:
///
/// A) Replace Binding with a `@MainActor` closure.
///    Closures have value semantics and are not registered with the SwiftUI
///    observation machinery, so there is nothing to retain or leak.
///
///    Why `@MainActor` and NOT `@Sendable`:
///    The closure is always invoked inside `Task { @MainActor in }`, so the
///    correct contract is "runs on main actor". `@Sendable` would mean "safe
///    from any thread" and requires every captured value to be Sendable —
///    producing the "may introduce data races" warning when the caller captures
///    @Observable state. `@MainActor` expresses the real intent.
///
/// B) The async dispatch is kept, but gated: only ONE async block is ever
///    dispatched — for the very first setup, before the view is in the hierarchy.
///    All subsequent updateUIView calls hit an early `guard` and return at zero
///    cost, breaking the feedback loop entirely.
struct ScrollOffsetReader: UIViewRepresentable {
    let collapseDistance: CGFloat
    /// @MainActor closure — never touches the SwiftUI observation registrar.
    let onProgress: @MainActor (CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // ── Why async is here but gated ──────────────────────────────────
        //
        // We NEED one async dispatch for the very first setup: at the moment
        // makeUIView returns, the UIView has no superview yet. findScrollView
        // would return nil and KVO would never be registered. Deferring by one
        // runloop tick lets UIKit insert the view into the scroll-view hierarchy.
        //
        // We do NOT want async on subsequent calls (fired ≤120×/sec as
        // collapseProgress updates). The guard below makes all those calls a
        // zero-cost early return — no allocation, no async, no storm.
        //
        // This is the precise fix: async exactly once at startup, never again.
        guard context.coordinator.trackedScrollView == nil else { return }

        DispatchQueue.main.async {
            context.coordinator.setup(
                in: uiView,
                distance: collapseDistance,
                onProgress: onProgress
            )
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        /// Internal so updateUIView can read it for the early-return guard
        /// without triggering a full setup() call.
        weak var trackedScrollView: UIScrollView?

        private var observation: NSKeyValueObservation?
        private var pendingTask: Task<Void, Never>?

        func setup(
            in view: UIView,
            distance: CGFloat,
            onProgress: @MainActor @escaping (CGFloat) -> Void
        ) {
            guard let scrollView = findScrollView(in: view) else { return }
            // Guard against redundant re-setup (e.g. if called twice on first tick).
            guard scrollView !== trackedScrollView else { return }

            trackedScrollView = scrollView
            observation?.invalidate()

            observation = scrollView.observe(
                \.contentOffset,
                options: [.new]
            ) { [weak self] sv, _ in
                guard let self else { return }

                let adjustedY = sv.contentOffset.y + sv.adjustedContentInset.top
                let p = min(max(adjustedY / distance, 0), 1.0)

                // Cancel any previously queued update so we never have more
                // than ONE pending Task in flight — the KVO storm killer.
                self.pendingTask?.cancel()
                self.pendingTask = Task { @MainActor in
                    guard !Task.isCancelled else { return }
                    onProgress(p)
                }
            }
        }

        deinit {
            pendingTask?.cancel()
            observation?.invalidate()
        }

        private func findScrollView(in view: UIView) -> UIScrollView? {
            var current: UIView? = view
            while let v = current {
                if let sv = v as? UIScrollView { return sv }
                current = v.superview
            }
            return nil
        }
    }
}
