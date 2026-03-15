# QuizFlash Architecture Reference

## Contents

- Project baseline
- Layer boundaries
- SwiftData and memory rules
- Concurrency rules
- Design system rules
- Navigation rules
- Scroll and presentation rules
- Code style and output rules
- Review checklist

## Project Baseline

- Target `iOS 17+`.
- Default stack: `Swift 6`, SwiftUI, SwiftData, `@Observable`, environment-based dependency injection.
- Treat this file as the intended standard for new code. Some existing files still predate these rules; do not spread those older patterns unless the task requires a contained fix.

## Layer Boundaries

| Path | Responsibility | Avoid |
|---|---|---|
| `Domain/Models/*.swift` | SwiftData `@Model` types and data helpers | SwiftUI/UIKit imports, presentation logic |
| `Features/*/ViewModels/*.swift` | Business logic, async orchestration, UI state | View references, layout math, rendering decisions |
| `Features/*/Views/*.swift` | SwiftUI rendering and action forwarding | Business rules, direct fetch logic |
| `Features/*/Components/*.swift` | Reusable mostly-stateless subviews | Owning `ModelContext`, `@Query`, or async tasks |

- Keep views dumb. Move business conditions and domain decisions into the view model or repository layer.
- Use repositories or actors for heavy data access instead of pulling model graphs into the main actor.

## SwiftData And Memory Rules

- Prefer denormalized counters like `deck.cardCount` and `folder.deckCount` instead of relationship `.count`.
- Default to `ModelContext.safeModel(for:as:)` from `Core/Extensions/ModelContext+SafeFetch.swift` when resolving models by identifier in app code.
- Keep each actor on its own `ModelContext(container)` with `autosaveEnabled = false`.
- Route card-content reads through `Domain/Repositories/CardFetchActor.swift` instead of loading `frontZoneData` or `backZoneData` on the main actor.
- On iOS 17, avoid `#Predicate` filters that traverse optional relationships such as `$0.deck?.persistentModelID == deckID` for hot paths. Resolve the parent model in the same context and read the relationship there instead. `CardFetchActor.fetchSnapshot(deckID:)` and `FlashCardsPlayModeViewModel.PlaybackActor.loadPlayableCards(for:)` are the canonical safe patterns.
- Flush actor-side contexts after heavy fetches so the row cache does not retain large model graphs longer than necessary.
- Wrap large per-card projection loops in `autoreleasepool` when decoding or flattening many cards in one pass. This reduces transient spikes for pathological decks on iOS 17.
- Call `card.clearZoneCache()` after background zone reads.
- Save explicitly with `do { try context.save() } catch { ... }`. Do not silently discard failures.

## Concurrency Rules

- Mark new `@Observable` view models as `@MainActor final class`.
- Use `Task { [weak self] in ... }` for stored tasks that call back into a view model.
- Cancel replaceable tasks before starting a new one.
- Use `await MainActor.run { }` or `Task { @MainActor in ... }` for main-actor mutations from async work.
- Avoid `DispatchQueue.main.async` in new code.
- Prefer `AsyncStream` for progressive result delivery when large data sets would otherwise block responsiveness.

## Design System Rules

- Use `UIConstants` tokens instead of hard-coded spacing, radius, size, or animation numbers.
- Use semantic colors first: `.primary`, `.secondary`, `Color(.systemBackground)`, `Color(.systemGroupedBackground)`, `Color(.label)`.
- Use `Color(hex:)` from `Core/Extensions/LibraryExtension.swift` when reading persisted deck or folder colors.
- Prefer theme access via environment-based plumbing for new UI code; do not introduce new theme singletons or ad hoc color sources.
- Use `.font(.system(size:weight:design: .rounded))` for display text and semantic text styles for body text.
- Reuse the standard motion presets from the original prompt:
  - Interactive change: `.spring(response: 0.35, dampingFraction: 0.85)`
  - Dismissal: `.spring(response: 0.35, dampingFraction: 0.8)`
  - Micro-interaction: `.easeInOut(duration: UIConstants.Animation.instant)`

### UIConstants Tokens

| Namespace | Values |
|---|---|
| `UIConstants.Spacing` | `tiny(4)`, `small(8)`, `medium(12)`, `standard(16)`, `large(20)`, `extraLarge(24)`, `huge(32)` |
| `UIConstants.Radius` | `small(8)`, `medium(12)`, `card(16)`, `large(22)`, `maximum(32)` |
| `UIConstants.Shadow` | `lightRadius(4)`, `mediumRadius(12)`, `heavyRadius(24)`, `yOffset(4)` |
| `UIConstants.Size` | `iconSmall(16)`, `iconStandard(24)`, `iconLarge(32)`, `buttonHeight(50)`, `cardMinHeight(120)` |
| `UIConstants.Animation` | `instant(0.15)`, `standard(0.25)`, `medium(0.35)`, `slow(0.5)` |

## Navigation Rules

- Use `Core/Navigation/NavigationManager.swift` and environment injection for programmatic navigation.
- Prefer `router.append(...)` and the repo's route types over direct `NavigationLink` orchestration for programmatic pushes.
- Freeze back-label values at push time instead of reading active-tab state reactively from pushed screens.
- Control tab bar visibility via the custom tab bar preference system rather than ad hoc global state.

## Scroll And Presentation Rules

- Treat iOS 17 scroll stability as a first-class architecture concern. The app has known cases where SwiftUI reconciliation resets `UIScrollView.contentOffset` during cover, sheet, menu, and navigation changes.
- For long-lived feature screens with floating top chrome, reserve top space with `.safeAreaInset(edge: .top)` based on the measured chrome height. Do not rely on overlay-only chrome plus hard-coded hero top padding.
- Use a local named coordinate space for hero-collapse detection on scrolling screens. Avoid `frame(in: .global)` checks when overlay chrome or safe-area values can shift during presentation.
- Use `Core/Helpers/ScrollPositionRestorer.swift` as the first child of the root scroll content when a screen must preserve pixel scroll offset across iOS 17 push/pop, sheet presentation, or other state-driven re-layouts.
- Persist the real pixel offset in the view model. Never write sentinel offsets like `1` to force restoration.
- Prefer `LazyVStack` or `LazyHStack` for large scroll surfaces. Do not build large eager `ForEach` trees inside a scroll view when deck or library data can grow significantly.
- Avoid `.scrollDisabled(...)` as a generic way to block interaction during menu overlays on iOS 17. Prefer hit-testing blockers when the goal is only to prevent taps while leaving the underlying scroll state untouched.
- Canonical examples for stable floating-chrome scroll layouts are `QuizFlash/Features/Library/Components/LibraryLayout.swift` and `QuizFlash/Features/DeckDetails/Views/DeckView.swift`.

### Custom Full-Screen Sheet

- Reuse `fullScreenSheet` from `Core/DesignSystem/Modifiers/View+FullScreenSheet.swift` for immersive presentations that need QuizFlash drag-dismiss behavior, custom background treatment, or safe-area aware full-screen content.
- Prefer item-based `fullScreenSheet(item:)` with an enum destination when one surface can open several modes. This keeps routing explicit and avoids a spread of booleans.
- Inside presented content, use `@Environment(\\.fullScreenSheetDismiss)` as the primary dismiss path and fall back to `dismiss()` only when the content is also used outside the custom sheet container.
- Pass a shared background builder instead of re-implementing backdrop logic in each screen.
- Use `dragDismissActivationHeight` or `.fullScreenSheetDragActivationHeight(...)` when drag-to-dismiss should only begin from the top chrome area.
- For heavy iOS 17 sheets, keep drag state in the lightweight outer container and host the presented SwiftUI tree inside one persistent `UIHostingController`. Do not rebuild the sheet content on every `offset` update. `View+FullScreenSheet.swift` is the canonical implementation.
- Do not pipe drag progress into static backgrounds or expensive chrome unless the effect is visually required. Route `fullScreenSheetDragProgress` only to backgrounds that actually animate from drag, otherwise keep the backdrop fully static.
- Prevent simultaneous sheet-drag plus inner-scroll on iOS 17. Freeze nested vertical scroll views while the sheet drag is active so the content does not overscroll and recompose during the same gesture.
- Do not replace these flows with `NavigationLink` or a plain system `sheet` when the existing product behavior depends on QuizFlash's custom full-screen sheet interaction model.
- Canonical examples are `QuizFlash/Features/DeckDetails/Views/DeckView.swift`, `QuizFlash/Features/PlayMode/FlashCardsMode/Views/FlashCardsPlayModeView.swift`, and `QuizFlash/Features/DeckEditor/Views/CreateCardView.swift`.

## Code Style And Output Rules

- Keep Apple-style file headers.
- Keep imports ordered and minimal.
- Keep explicit `// MARK: -` sections.
- Add DocC comments to new public and internal declarations, with emphasis on why the code exists.
- Keep comments in English.
- Prefer `Logger` or `os_log` over `print`.
- Use static formatter instances instead of inline `DateFormatter()` allocation.
- Do not emit `TODO:`, `FIXME:`, or commented-out dead code in generated output.

## Review Checklist

- Check that no new code reads relationship arrays just to compute `.count`.
- Check that no new main-actor code loads heavy card blobs directly.
- Check that stored tasks are cancellable and cancelled on replacement.
- Check that new `@Observable` view models are `@MainActor`.
- Check that saves are explicit and failures are logged or surfaced.
- Check that new images go through `ImageCache` and new web views go through `MathWebViewPool`.
- Check that new long scroll surfaces use lazy stacks and stable chrome spacing instead of hard-coded overlay compensation.
- Check that new immersive modal flows reuse `fullScreenSheet` when they need the app's custom drag-dismiss and backdrop behavior.

