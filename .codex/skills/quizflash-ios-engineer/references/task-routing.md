# Task Routing

Use this file to minimize context for existing-file tasks. Default rule:

`target file -> smallest paired owner file -> shared references on demand`

Do not start by reading broad repo docs unless the task actually needs them.

## Context Budget Procedure

When the user describes a bug from screenshots, videos, UI copy, or behavior but does not name files:

1. Infer the smallest likely feature area from visible UI text, controls, and mode names.
2. Run `rg` for those UI strings, symbols, route names, or distinctive model names before reading files.
3. Open only 2-4 likely owner files first. Prefer slices around matching symbols over full-file reads.
4. Expand to 5-7 files only when a concrete cross-file contract is involved, such as a view forwarding gestures into a UIKit wrapper or a persisted model feeding a renderer.
5. Before reading broad references or a whole feature cluster, state the specific missing fact that requires it.
6. Stop reading once the root-cause hypothesis is testable; patch and verify instead of collecting more context.

For video-heavy UI debugging, extract a few representative frames first and use the video only for timing-sensitive gesture or animation issues.

## Escalation Triggers

- Read `project-map.md` only when ownership, placement, or feature boundaries are unclear.
- Read the relevant parts of `architecture.md` only when the task touches:
  - SwiftData fetches, saves, model graph access, or memory-sensitive reads
  - Stored tasks, async pipelines, actor boundaries, or cancellation
  - Navigation, `fullScreenSheet`, sticky chrome, long scroll surfaces, or shared adaptive layout infrastructure
  - Shared design-system rules or cross-screen presentation behavior
- Read `component-catalog.md` only before creating a new reusable UI component.
- Read `antipatterns.md` only when extending legacy code patterns or doing cleanup beyond the local fix.
- Read `new-feature-template.md` and the examples only for new screens or end-to-end features.

## Paired Owner Rules

- `Features/*/Views/*.swift`
  Open the paired `ViewModels/` file only if the change touches state, async work, persistence, derived data, or navigation owned outside the view.
- `Features/*/Components/*.swift`
  Open the parent view or local layout/helper file only if the component does not fully explain the change by itself.
- `Features/*/ViewModels/*.swift`
  Open the paired root `Views/` file only if UI wiring, presentation, or event forwarding changes.
- `Domain/Models/*.swift`
  Pull `architecture.md` only if the change touches SwiftData safety, relationships, or persistence patterns.

## Routes

### Home small UI tweak

- Start with the touched file under `Features/Home/Views/` or `Features/Home/Components/`.
- If the task is calendar spacing, compact state, or header geometry, add `Features/Home/Components/HomeCalendarAdaptiveLayout.swift`.
- Add `Features/Home/Views/HomeView.swift` only if the change depends on query-fed inputs or coordinator wiring.
- Add `Features/Home/ViewModels/HomeViewModel.swift` only if the change affects summaries, derived data, or actions.
- Read `architecture.md` only for long-scroll, sticky chrome, or shared adaptive-layout behavior.

### Home data or snapshot change

- Start with `Features/Home/ViewModels/HomeViewModel.swift`.
- Add `Features/Home/Views/HomeView.swift` for query inputs and update triggers.
- Add `Features/Home/ViewModels/CalendarViewModel.swift` only if the change touches date selection, month paging, or week-start behavior.
- Read the SwiftData and performance sections of `architecture.md` only if fetch, caching, or heavy derived work changes.

### DeckWorkspace local UI tweak

- Start with `Features/DeckEditor/Views/DeckWorkspaceView.swift` or the local deck-editor view/component you are changing.
- Add `Features/DeckEditor/ViewModels/DeckWorkspaceViewModel.swift` only if the change touches state, actions, save gating, or derived view-model data.
- Do not open `Services/AI/*` for copy, spacing, toolbar, dialog, or overlay tweaks that stay inside the existing view-model contract.
- Read `architecture.md` only for `fullScreenSheet`, sticky chrome, long-scroll, or navigation behavior.

### Flashcard zone editor interaction/layout bug

Use this route for card-zone editing issues: caret placement, long-press selection, focus/unfocus jumps, resize handles, raw text editor metrics, toolbar overlap, keyboard avoidance, editor/play preview parity, or visual zone outlines.

- Start with the narrow symptom:
  - Text input, caret, selection, focus state: `Features/DeckEditor/ZoneLogic/ZoneTextView.swift`, then `Features/DeckEditor/ZoneLogic/ZoneFocusManager.swift`.
  - Zone frame, resize, hit testing, handles, empty-zone sizing: `Features/DeckEditor/Views/ZoneView.swift`, then the local resize/helper symbols found by `rg "resize|handle|ZoneResize|minimum|caret" Features/DeckEditor`.
  - Toolbar, keyboard, scroll, canvas placement: `Features/DeckEditor/Views/FlashcardEditorView.swift`, then `Features/DeckEditor/Components/EditorFormatMenuBar.swift`.
  - Editor/play size or wrapping mismatch: `Features/DeckEditor/Components/FlashcardGridContentLayout.swift` plus the exact play-mode renderer found by `rg "FlashcardGridContentLayout|contentAlignment|textSize" Features Domain`.
- Do not open `MixedMathTextView.swift` for raw editor bugs unless the issue explicitly involves compiled math/rich preview or play-mode rendering.
- Do not read `project-map.md` or `architecture.md` for local cursor, focus, resize, or outline bugs unless the fix crosses shared sheet/navigation/long-scroll infrastructure.
- Keep UIKit wrapper and SwiftUI container reads paired. Most bugs here come from a contract mismatch between `UITextView` behavior, SwiftUI frame updates, focus state, and gesture hit testing.
- If the same class of editor bug has already been patched repeatedly, add temporary instrumentation or a debug overlay before making another blind layout tweak.
- Preserve these invariants while fixing:
  - Focus/unfocus must not change text width, line wrapping, padding, or zone position.
  - Simple tap places the caret; native selection starts only from long press, drag handles, or double tap.
  - Resize cannot cut existing text below its measurable raw-text minimum, but it must allow shrinking when visual slack exists.
  - Empty zones keep a stable editable minimum area after focus leaves.

### DeckWorkspace AI behavior

- Start with `Features/DeckEditor/ViewModels/DeckWorkspaceViewModel.swift`.
- Add the narrowest AI files involved:
  - `Services/AI/AIFlashcardService.swift` for generation pipeline behavior
  - `Services/AI/AIWorkspaceCoordinator.swift` for workspace generation lifecycle and restore behavior
  - `Services/AI/AIGenerationState.swift` for state shape or diagnostics
- Add `Features/DeckEditor/Views/DeckWorkspaceView.swift` only if the surfaced UI contract changes.
- Read concurrency and SwiftData sections in `architecture.md` for task lifecycle or persistence changes.

### DeckView chrome or grid tweak

- Start with `Features/DeckDetails/Views/DeckView.swift`, `Features/DeckDetails/Views/DeckCardGridView.swift`, or the touched component under `Features/DeckDetails/Components/`.
- Add `Features/DeckDetails/ViewModels/DeckViewModel.swift` only if the change touches selection state, actions, mutations, or snapshot loading.
- Read `architecture.md` only for `fullScreenSheet`, sticky chrome, long-scroll surfaces, or performance-sensitive grid behavior.

### DeckView mutation or behavior change

- Start with `Features/DeckDetails/ViewModels/DeckViewModel.swift`.
- Add `Features/DeckDetails/Views/DeckView.swift` for UI wiring and user actions.
- Pull `Domain/Repositories/CardFetchActor.swift` or cache helpers only if the change reaches fetch or background snapshot behavior.
- Read SwiftData and performance sections in `architecture.md` only if persistence, actor boundaries, or memory-sensitive card reads change.

### Settings local tweak

- Start with the specific file under `Features/Settings/Views/`.
- Do not open broad repo docs by default.
- Read `architecture.md` only if the change adds persistence, navigation infrastructure, or shared presentation behavior.
- Read `component-catalog.md` only if you are extracting a new reusable settings row or shared control.

### PlayMode settings tweak

- Start with `Features/PlayMode/Shared/PlayModeSettingsScreen.swift`.
- Add `Domain/Models/DeckPlayModeSettingsModel.swift` only if the persisted settings shape changes.
- Add mode-specific settings types only if the change reaches mode contracts rather than local UI.
- Read `architecture.md` only if the change touches persistence safety or `fullScreenSheet` behavior.

### Unknown UI owner from screenshot or screen recording

- Start with `rg` on visible labels, button text, accessibility labels, and distinctive debug strings.
- If the UI is a sheet, search both the presented view and the custom sheet/presentation wrapper before touching global gesture code.
- If a bug appears in both preview and play mode, find the shared renderer or model first; do not patch each surface separately unless they intentionally diverge.
- If a tap/drag is ignored, inspect competing gestures and UIKit representables before changing visual layout.

## Fast Rejection Rules

- A text, copy, spacing, or local overlay change should not automatically pull `project-map.md`.
- A local Home or DeckView UI tweak should not automatically pull `architecture.md` end to end.
- A `DeckWorkspaceView` UI tweak should not automatically pull the whole AI stack.
- A flashcard zone-editor touch or layout bug should not automatically pull every `Features/DeckEditor` file.
- A screenshot/video bug should not start with broad repo docs; use `rg` and a small owner-file set first.
- If two nearby files explain the change safely, stop there and edit.
