# QuizFlash Architecture Reference

## Contents

- Project baseline
- Layer boundaries
- SwiftData and memory rules
- Concurrency rules
- Design system rules
- Navigation rules
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
- Flush actor-side contexts after heavy fetches so the row cache does not retain large model graphs longer than necessary.
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
