# Task Routing

Use this file to minimize context for existing-file tasks. Default rule:

`target file -> smallest paired owner file -> shared references on demand`

Do not start by reading broad repo docs unless the task actually needs them.

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

### DeckWorkspace AI behavior

- Start with `Features/DeckEditor/ViewModels/DeckWorkspaceViewModel.swift`.
- Add the narrowest AI files involved:
  - `Services/AI/AIFlashcardService.swift` for generation pipeline behavior
  - `Services/AI/AIWorkspaceCoordinator.swift` for workspace conversion flows
  - `Services/AI/AIGenerationState.swift` for state shape or diagnostics
- Add `Features/DeckEditor/Views/DeckWorkspaceView.swift` only if the surfaced UI contract changes.
- Read concurrency and SwiftData sections in `architecture.md` for task lifecycle or persistence changes.

### DeckView chrome or grid tweak

- Start with `Features/DeckDetails/Views/DeckView.swift`, `Features/DeckDetails/Views/DeckCardGridView.swift`, or the touched component under `Features/DeckDetails/Components/`.
- Add `Features/DeckDetails/ViewModels/DeckViewModel.swift` only if the change touches selection state, actions, mutations, conversion, or snapshot loading.
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

## Fast Rejection Rules

- A text, copy, spacing, or local overlay change should not automatically pull `project-map.md`.
- A local Home or DeckView UI tweak should not automatically pull `architecture.md` end to end.
- A `DeckWorkspaceView` UI tweak should not automatically pull the whole AI stack.
- If two nearby files explain the change safely, stop there and edit.
