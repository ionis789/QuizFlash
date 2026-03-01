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

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        // 🔥 CRITICAL FIX: SwiftUI's internal UIHostingController aggressive caching
        // means UIScrollViews might outlive the DeckView screen.
        // We MUST explicitly break the KVO observation when this view leaves the hierarchy,
        // otherwise the UIScrollView permanently retains the `onProgress` closure,
        // which strongly retains the `DeckViewModel` and leaks megabytes of data on every screen visit!
        coordinator.cleanup()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        weak var trackedScrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        // ✅ FIX 1: Adăugăm un deduplicator pentru a evita suprasolicitarea
        private var lastProgress: CGFloat = -1.0

        func setup(
            in view: UIView,
            distance: CGFloat,
            onProgress: @MainActor @escaping (CGFloat) -> Void
        ) {
            guard let scrollView = findScrollView(in: view) else { return }
            guard scrollView !== trackedScrollView else { return }

            trackedScrollView = scrollView
            observation?.invalidate()

            let baseline = scrollView.adjustedContentInset.top

            // ✅ Observăm și valoarea veche (.old) pentru a detecta anomaliile
            observation = scrollView.observe(
                \.contentOffset,
                options: [.old, .new]
            ) { [weak self] sv, change in
                guard let self else { return }

                let oldY = change.oldValue?.y ?? 0
                let newY = change.newValue?.y ?? 0

                // ✅ FIX 2: Filtru Anti-Glitch (Navigation Pop iOS 17)
                // În timpul animației de întoarcere, SwiftUI aruncă offset-ul la 0
                // pentru un singur frame. Dacă saltul e masiv (> 500pt) și utilizatorul
                // nu atinge ecranul, e un glitch de sistem. Îl ignorăm complet!
                if abs(newY - oldY) > 500 && !sv.isTracking && !sv.isDecelerating {
                    return
                }

                let adjustedY = newY + baseline
                let p = min(max(adjustedY / distance, 0), 1.0)

                // ✅ FIX 3: Deduplicare
                // Nu trezim SwiftUI-ul dacă progresul a rămas la fel (ex: când e deja 1.0)
                guard p != self.lastProgress else { return }
                self.lastProgress = p

                // ✅ FIX 4 CRITIC: Evadarea din Layout Pass
                // Amânăm notificarea stării pentru următorul ciclu runloop.
                // Asta împiedică distrugerea cache-ului LazyVStack-ului din cauza
                // modificărilor de stare făcute în timpul `layoutSubviews`.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        onProgress(p)
                    }
                }
            }
        }

        func cleanup() {
            observation?.invalidate()
            observation = nil
            trackedScrollView = nil
        }

        deinit {
            cleanup()
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

// MARK: - ScrollRestorer (iOS 17 iOS Native Scroll Saver)

/// A robust UIKit bridge that directly reads and writes the native `UIScrollView.contentOffset`.
/// Because SwiftUI dynamically destroys layout bounds during NavigationStack pops on iOS 17,
/// this bypasses the View layer entirely and forces the UIScrollView back to its recorded position.
struct ScrollOffsetSaver: UIViewRepresentable {
    @Binding var scrollOffset: CGFloat

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard context.coordinator.trackedScrollView == nil else { return }

        DispatchQueue.main.async {
            context.coordinator.setup(in: uiView, offset: $scrollOffset)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.cleanup()
    }

    class Coordinator: NSObject {
        weak var trackedScrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var isRestoring = false
        private var offsetBinding: Binding<CGFloat>?

        func setup(in view: UIView, offset: Binding<CGFloat>) {
            self.offsetBinding = offset
            guard let scrollView = findScrollView(in: view) else { return }
            guard scrollView !== trackedScrollView else { return }

            trackedScrollView = scrollView
            observation?.invalidate()

            // 1. Force structural restoration immediately.
            if offset.wrappedValue > 0 {
                isRestoring = true
                attemptRestoration(scrollView: scrollView, targetY: offset.wrappedValue, attemptsLeft: 10)
            }

            // 2. Track outgoing scroll position via KVO
            observation = scrollView.observe(
                \.contentOffset,
                options: [.new]
            ) { [weak self] sv, change in
                guard let self = self, !self.isRestoring else { return }
                guard let newY = change.newValue?.y else { return }

                // SwiftUI momentarily zeroes the offset during navigation pushes.
                // If it suddenly drops to exactly 0 while we were deep in the list, ignore it.
                if newY <= 0 && (self.offsetBinding?.wrappedValue ?? 0) > 100 {
                    return
                }

                // If the user drops below 0 (rubber banding at the top), 
                // we treat it as 0 for restoration purposes.
                let safeY = max(newY, 0)
                
                // We only write to the binding occasionally to prevent 120Hz view invalidation storms.
                // Using an async dispatcher gets us off the main render pipeline pass.
                DispatchQueue.main.async {
                    let current = self.offsetBinding?.wrappedValue ?? 0
                    if abs(safeY - current) > 1.0 {
                        self.offsetBinding?.wrappedValue = safeY
                    }
                }
            }
        }

        private func attemptRestoration(scrollView: UIScrollView, targetY: CGFloat, attemptsLeft: Int) {
            guard attemptsLeft > 0 else {
                DispatchQueue.main.async { self.isRestoring = false }
                return
            }
            
            // The maximum allowable Y offset for the current content size.
            // LazyVStack starts small and grows as we scroll down.
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
            
            if targetY <= maxY || maxY == 0 {
                // The LazyVStack has expanded enough to support our target offset, OR 
                // geometry calculation hasn't run even once yet (maxY == 0).
                scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
                
                // If we succeeded in hitting the exact target geometry, we are done.
                if targetY <= maxY {
                    DispatchQueue.main.async { self.isRestoring = false }
                    return
                }
            } else {
                // LazyVStack hasn't expanded far enough yet. 
                // Force an aggressive scroll to the very bottom to trigger the next batch of views to render.
                scrollView.setContentOffset(CGPoint(x: 0, y: maxY), animated: false)
            }
            
            // Retry on the next runloop frame, giving SwiftUI time to materialize the new cells
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak scrollView] in
                guard let self = self, let sv = scrollView else { return }
                self.attemptRestoration(scrollView: sv, targetY: targetY, attemptsLeft: attemptsLeft - 1)
            }
        }

        func cleanup() {
            observation?.invalidate()
            observation = nil
            trackedScrollView = nil
            offsetBinding = nil
        }

        deinit {
            cleanup()
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
