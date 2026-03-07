# iOS 17 Collapsing Header — Micro-Lag Handover

## Context

SwiftUI app (QuizFlash) with a custom collapsing header built on a `UIViewControllerRepresentable` called `iOS17ScrollHost`. The header animates opacity/scale based on `collapseProgress: CGFloat` (an `@Observable` property on `LibraryViewModel`).

Architecture:
- `CollapsingScrollView` (SwiftUI) wraps `iOS17ScrollHost` in a ZStack
- `iOS17ScrollHost` is a `UIViewControllerRepresentable` that owns a `UIScrollView`
- `UIScrollViewDelegate.scrollViewDidScroll` emits progress to SwiftUI via a `@MainActor` closure
- The closure writes `viewModel.collapseProgress = p` which drives header animations

## The Problem

When scrolling slowly, the collapsing header transformation has a **micro-lag / easing feel** — as if there's an implicit animation being applied to `collapseProgress`. The transition between "expanded" and "collapsed" header states does not track the finger 1:1. It feels like a ~0.2–0.3s ease is being applied even though no explicit animation is intended.

The same symptom appears in both directions: scrolling down (header collapsing) and scrolling up (header expanding).

## What Was Tried (All Failed)

### Attempt 1 — `Task { @MainActor in onProgress(p) }`
Original implementation used an async Task to hop to MainActor before calling onProgress.
**Result:** Made the lag slightly worse (~16ms extra per frame from Task scheduling overhead).

### Attempt 2 — `MainActor.assumeIsolated { onProgress(p) }`
Since UIKit's `scrollViewDidScroll` already runs on the main thread, replaced async Task with `MainActor.assumeIsolated` for synchronous execution.
**Result:** No improvement. The lag remained identical.

### Attempt 3 — `withTransaction(Transaction(animation: nil)) { onProgress(p) }` + `t.disablesAnimations = true`
Hypothesis: SwiftUI was inheriting an active animation transaction from NavigationStack or a parent `withAnimation` call, causing `collapseProgress` to be animated rather than set instantly.
```swift
MainActor.assumeIsolated {
    var t = Transaction(animation: nil)
    t.disablesAnimations = true
    withTransaction(t) { onProgress(p) }
}
```
**Result:** No improvement. The lag remained identical.

## Architecture Details

```swift
// iOS17ScrollHost — UIScrollViewDelegate
func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard !isApplyingRestoration else { return }
    let p = progressFor(rawOffsetY: scrollView.contentOffset.y)
    MainActor.assumeIsolated {
        var t = Transaction(animation: nil)
        t.disablesAnimations = true
        withTransaction(t) { onProgress(p) }
    }
}
```

```swift
// CollapsingScrollView — passes the closure
iOS17ScrollHost(
    ...
    onProgress: onProgress,  // @MainActor (CGFloat) -> Void
    ...
)
```

```swift
// LibraryLayout — the closure body
CollapsingScrollView(
    onProgress: { p in viewModel.collapseProgress = p },
    ...
)
```

```swift
// LibraryHeroSection — reads collapseProgress
.opacity(1.0 - t)
.scaleEffect(1.0 - (t * 0.4), anchor: .topLeading)
.offset(y: -(t * 20))
// No explicit .animation modifier here
```

```swift
// LibraryTopBarView — also reads collapseProgress for compact title
// Has its own opacity/offset animations driven by the same value
```

## Hypothesis for Root Cause (Unverified)

The lag may not be in the *write path* (`onProgress`) but in the *read path*. SwiftUI's `@Observable` tracking system may be batching `collapseProgress` updates with other pending state changes and flushing them together at the end of the runloop, rather than immediately per `scrollViewDidScroll` call. This would mean the view renders 1–2 frames behind the actual scroll position.

Alternatively, `UIHostingController` (used internally by `UIViewControllerRepresentable`) may be applying its own implicit transaction when bridging SwiftUI state updates from UIKit context.

## What a Correct Solution Might Look Like

The ideal fix would ensure `collapseProgress` is read and rendered in the **same CADisplayLink frame** as the `scrollViewDidScroll` call. Possible approaches to investigate:

1. **CADisplayLink instead of scrollViewDidScroll** — read `scrollView.contentOffset` directly on the display link callback, bypassing UIKit's delegate timing
2. **UIViewRepresentable instead of UIViewControllerRepresentable** — a lighter UIKit bridge that avoids UIHostingController's transaction batching
3. **GeometryEffect or AnimatableModifier** — bypass `@Observable` entirely and drive the header transform directly from a custom layout pass
4. **Eliminate the bridge entirely** — render the header as a UIKit view overlaid on the UIScrollView, zero SwiftUI involvement in the hot path

## Files Involved

- `iOS17ScrollHost.swift` — the UIViewControllerRepresentable (main file)
- `CollapsingScrollView.swift` — SwiftUI wrapper, ZStack on iOS 17
- `LibraryLayout.swift` — caller, passes `{ p in viewModel.collapseProgress = p }` as onProgress
- `LibraryViewModel.swift` — `@Observable`, holds `collapseProgress: CGFloat = 0`
- `LibraryContentViews.swift` — `LibraryHeroSection` and `LibraryTopBarView` read collapseProgress

## Constraints

- iOS 17 minimum deployment target for this code path
- iOS 18 path works perfectly via `.onScrollGeometryChange` (native, no lag)
- Cannot use `.scrollPosition`, `PreferenceKey + GeometryReader` (causes LazyVStack cache invalidation and re-render flash on NavigationStack pop)
- The fix must NOT reintroduce the NavStack pop flash (previously solved by using `UIViewControllerRepresentable` with `viewWillAppear` offset restoration)
- `LibraryDeckListRow` must use eager `VStack` on iOS 17 (not LazyVStack) for correct `contentSize` — this constraint is fixed and working
