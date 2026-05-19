---
name: quizflash-ios-engineer
description: Project-specific engineering guide for QuizFlash, a SwiftUI flashcard app targeting iOS 17+ with Swift 6, SwiftData, and `@Observable`. Use when Codex writes, reviews, debugs, or refactors code in this repository, especially for SwiftUI views, view models, SwiftData models, background fetch actors, navigation, theming, memory/performance work, and QuizFlash file-format or output conventions.
---

# QuizFlash iOS Engineer

## Overview

Write and review code for QuizFlash using the repository's architecture rules instead of generic SwiftUI defaults. Optimize for the smallest safe context: start from the target file, load the paired owner file next, and pull longer references only when the task actually crosses those boundaries. Treat the standards in `references/architecture.md` as the target for new code even when older files still contain legacy patterns.

QuizFlash no longer ships an exam-goals feature on Home. Treat `Home` as a study dashboard focused on calendar activity, recent decks, folders, and performance summaries. Do not introduce or preserve `ExamGoalModel`, exam-goal sheets, exam readiness widgets, or calendar exam markers unless the user explicitly asks to reintroduce that product area.

Keep UI copy terse. Do not add explanatory filler, repeated titles, helper paragraphs, or decorative subtitles unless they are necessary for the screen to function. Default to the minimum viable copy on primary surfaces: if a label, subtitle, helper line, or decorative text can be removed without harming clarity, remove it. This applies especially to development/internal screens and settings surfaces.

QuizFlash now ships multi-language UI and all new app-owned copy must be localization-ready. The supported UI languages are English (`en`), Romanian (`ro`), and Russian (`ru`). Do not hardcode user-facing app copy behind plain runtime `String` properties when that would bypass localization; prefer `LocalizedStringResource`, existing localized helper methods that accept `Locale`, or explicit prelocalized strings when runtime values must cross navigation/state boundaries. When adding or changing app-owned copy, update every supported language, not just English. User-authored content such as deck titles, folder names, and card text must remain verbatim and must not be routed through app-string localization.

QuizFlash uses an app-language bundle override, not just SwiftUI environment locale, to resolve localized strings. Do not assume `locale` alone will switch the lookup language for `String(localized:)` or other bundle-backed copy. For app-owned UI copy, prefer `AppLocalization.string(...)` / `AppLocalization.numbered(...)` over direct `String(localized: ..., locale: ...)`; the direct form has already caused real regressions where dates localized correctly but UI copy stayed in English. If localization infrastructure changes, keep `AppLocalization.applyLanguageOverride(...)` wired so bundle lookup and date/number formatting stay in sync. For quick vocabulary edits across all supported languages, keep `Docs/UI-Dictionary/localization_matrix.py` working: it exports and imports the shared `key / en / ro / ru` table used for review and bulk editing.

Treat `Docs/UI-Dictionary/localization_matrix.tsv` as the human-editable source of truth for app-owned UI vocabulary review. When adding, changing, or removing app-owned copy, update the underlying localization keys for all supported languages and keep the matrix in sync in the same task. Do not leave new copy only in `.strings` files without regenerating the matrix, and do not remove copy from code while leaving stale keys behind in the matrix unless the task explicitly preserves them for later reuse. The default workflow is: edit code + localized values, then run the matrix export/import flow so reviewers can inspect wording from one table instead of diffing raw `.strings` files.

Preserve layout stability on dynamic scroll surfaces. When selected dates, filters, live counters, or other in-place state changes can swap text or metrics inside a scrolling screen, reserve stable heights for the affected slots so the surrounding card or section does not jump and disturb scroll position. Avoid springy or bouncy text motion for these changing values unless the user explicitly asks for that treatment.

Treat animation smoothness as a first-class product requirement. For visible transitions, avoid mounting expensive SwiftUI subtrees, recomputing large layouts, observing per-frame geometry, or triggering persistence/async work on the same state edge that starts the animation. Prefer animating cheap layer-friendly properties such as opacity, scale, and transform on already-mounted views; keep keyboard, scroll, and toolbar animations isolated so they do not invalidate each other.

When animation or interaction lag survives an initial optimization, lead with an explicit debugging protocol instead of passively waiting for another symptom report. Add narrowly scoped DEBUG-only visual instrumentation when useful, tell the user exactly what gesture/video to capture, and explain which metrics will confirm or reject the current hypothesis.

Do not route per-frame scroll offsets through observed SwiftUI state. Persist scroll restoration offsets in `@ObservationIgnored` view-model storage or other non-observed holders so scroll probes do not invalidate an entire screen on every drag tick.

On iOS 17, do not reconfigure live blur/filter layers during scroll-driven updates. If a root surface needs a top progressive blur, keep the `UIViewRepresentable` stable and mutate only cheap scalar inputs such as opacity or an already-attached radius value. Avoid calling layer/filter refresh code from `updateUIView` on every drag tick; use a static fallback only when a stable live path is not available.

Treat iOS 17.5 as the strict compatibility baseline for SwiftUI/UIKit presentation behavior. Do not assume behavior that works on iOS 18, iOS 26, or a physical newer-OS device is valid on iOS 17. Be especially conservative around `UIViewRepresentable` / `UIViewControllerRepresentable` hosted inside SwiftUI containers, custom sheets, masks/clips, `.compositingGroup()`, material/blur surfaces, gesture recognizers, and overlays. On iOS 17 these combinations can render correctly while hit-testing, scroll interaction, or gesture delivery is broken. When masking interactive hosted content, prefer UIKit-level clipping on the hosted view/controller or clip only non-interactive visual layers; avoid wrapping the whole interactive host in SwiftUI compositing + clip unless it has been verified on iOS 17.5.

Use the current DeckEditor naming. `CardEditorView` is the router from `CardEditorDestination` into concrete editor surfaces. `FlashcardEditorView` owns the zone-based front/back flashcard editor. `QuizCardEditorView`, `MatchCardEditorView`, and `WriteCardEditorView` own their respective typed card authoring flows. Do not reintroduce pre-refactor create/add-card sheet aliases in new code, docs, logs, or comments.

Default QuizFlash custom sheets to full-surface drag-dismiss. Do not restrict drag activation to a top strip unless the sheet contains interaction-heavy full-screen content that would become error-prone with full-height dismissal. For standard detail/configuration sheets, the user should be able to drag down from anywhere on the sheet.

Synchronize custom sheets and the floating tab bar by starting both animations from the same event. Do not wait for a sheet presentation binding to clear, a `PreferenceKey` to propagate, or the sheet view to disappear before revealing the tab bar; that creates a visible delay even when each individual animation is smooth. `fullScreenSheet` owns sheet-scoped tab-bar hiding through the explicit sheet visibility channel in `MainAppView`, releasing it at dismiss start so the tab bar reveal begins in parallel with the sheet dismissal. Keep screen-level `.customTabBarVisibility` for screen-owned states such as selection, search, keyboard/edit focus, and pushed editors, not for sheet lifecycle timing.

Keep all app top chrome on one vertical rhythm. Floating top menus, back buttons, title pills, circular actions, and immersive play-mode headers must align to the shared top anchor used by Library and Deck chrome: `safeTopInset + UIConstants.Layout.deckNavigationTopPadding`, or the shared `.topNavigationChrome(...)` modifier when the surface is not manually managing safe-area geometry. Do not add local extra offsets such as `safeTopInset + 30` in one flow; if a screen needs more breathing room, move the content below the chrome rather than moving the chrome itself.

For immersive play-mode sheets, do not present an empty full-screen shell while the first playable payload is still loading. Prepare the initial visible payload or session view model before setting the sheet item, then pass the prepared state into the sheet. The first visible frame of a gameplay sheet should already have its primary card/content attached; use background continuation only for non-visible remaining data.

When external framework or library behavior matters, prefer the best available primary documentation source before relying on memory. Use `Context7` when that MCP is available for current third-party API docs, examples, and recent usage guidance; fall back to official docs or primary sources when `Context7` is unavailable.

Use these priority levels consistently:
- `MUST`: hard constraint unless the user explicitly overrides it.
- `SHOULD`: default behavior; deviate only when the local task clearly benefits.
- `MAY`: optional helper guidance.

## Quick Start

1. `MUST` open the target file first.
2. `SHOULD` read `references/task-routing.md` before expanding context when the smallest safe path is not obvious.
3. `MUST` open the smallest paired owner file next.
   - `Features/*/Views/*.swift`: pull the paired `ViewModels/` file only if the change touches state, async work, persistence, derived data, or navigation owned outside the view.
   - `Features/*/Components/*.swift`: pull the parent view or local layout/helper file only if the component does not fully explain the behavior by itself.
   - `Features/*/ViewModels/*.swift`: pull the paired root `Views/` file only if UI wiring or presentation behavior changes.
4. `MAY` read `references/project-map.md` when ownership is unclear or you are adding or moving types.
5. `SHOULD` read only the relevant parts of `references/architecture.md` when the task touches:
   - SwiftData fetches, saves, model-graph access, or memory-sensitive reads
   - Stored tasks, async pipelines, actor boundaries, or cancellation
   - Navigation, `fullScreenSheet`, sticky chrome, long scroll surfaces, or adaptive layout infrastructure
   - Shared design-system behavior, tokens, or reusable cross-screen presentation rules
   - Multi-layer refactors or reviews that cross feature boundaries
6. `SHOULD` verify `references/component-catalog.md` before creating a new reusable UI component.
7. `SHOULD` reuse existing project primitives before introducing new abstractions.
   Frequent examples include:
   - `NavigationManager`
   - `UIConstants`
   - `ThemeManager`
   - `ModelContext.safeModel(for:as:)`
   - `CardFetchActor`
   - `fullScreenSheet` from `Core/DesignSystem/Modifiers/View+FullScreenSheet.swift`
   - `StandardSheetTopStripBackground`
   Use `references/project-map.md` and `references/component-catalog.md` as the authoritative inventory instead of treating this list as exhaustive.
8. `MAY` prefer the `ios-simulator` MCP for simulator-supported UI validation when it is available:
   - inspect accessibility elements on screen
   - verify tap/swipe/text-entry flows after UI changes
   - capture screenshots or recordings for visual regressions
   - use it as a fast QA pass before or alongside manual device verification

## Context Budget Protocol

Use progressive disclosure for every task, even when the user gives only a bug report, screenshot, or video and does not name files.

1. `MUST` infer the smallest likely owner area from user language and visible UI before reading code.
   - Examples: "flashcard editor zones", "match play", "preview sheet", "deck grid", "settings text size".
2. `MUST` start with `rg` discovery, not broad file reads, when exact files are not named.
   - Search for unique visible labels, view names, symbols, debug HUD text, or feature terms.
   - Prefer `rg --files` and `rg "symbol"` over opening directories or long files.
3. `MUST` read code in slices with `sed -n` around relevant symbols.
   - Do not dump full files over roughly 350 lines unless the file itself is small or the first targeted reads prove the whole file is needed.
   - Do not dump full `git diff` for a dirty repo; restrict diff to touched or suspected files.
4. `SHOULD` keep the initial code read set to 2-4 files for local UI/interaction bugs.
   - Expand to 5-7 files only after identifying a concrete cross-file contract, such as a binding, environment object, shared layout engine, or notification.
5. `MUST` state the escalation reason before reading a broad reference or another feature cluster.
   - Good: "The view only forwards state; I need the view model mutation owner."
   - Bad: "I'll read architecture/project-map just in case."
6. `MUST NOT` read `references/project-map.md`, `references/architecture.md`, or `references/component-catalog.md` by default for a local bug.
   - Use `task-routing.md` first.
   - Pull only the relevant reference section when the local code does not explain ownership or safety.
7. `MUST` stop reading once the current hypothesis has enough evidence for a focused patch.
   - Prefer a small patch plus targeted build over a large speculative refactor.
   - If the same symptom has already resisted two fixes, switch to targeted instrumentation before more behavioral changes.
8. `SHOULD` extract only a few representative frames from videos unless frame-by-frame timing matters.
   - Use 3-8 frames around the failure and user-provided timestamps when available.
   - Do not transcribe or inspect an entire video unless the bug depends on gesture timing.

When context is already large, summarize findings and continue from the narrowed owner files instead of reopening broad references.

## Context Loading Rules

- `MUST` prefer the smallest viable read set for edits to existing files.
- `MUST NOT` preload unrelated feature clusters just because the repo has shared architecture docs.
- `MUST` escalate from local files to shared references only when the task crosses a boundary that the local files do not explain safely.
- Examples:
  - `DeckWorkspaceView.swift` copy, spacing, or overlay tweaks should start in `DeckWorkspaceView.swift` plus the narrow owning extension/component; do not read `AIFlashcardService.swift` unless the change reaches AI pipeline behavior.
  - `HomeCalendarSectionView.swift` spacing or compact-calendar tweaks should start in `HomeCalendarSectionView.swift` plus `HomeCalendarAdaptiveLayout.swift`; pull `HomeViewModel.swift` only if the change touches summaries or derived data.
  - `DeckView.swift` dialog, toolbar, or overlay copy tweaks should start in `DeckView.swift`; pull `DeckViewModel.swift` only if the action, mutation, or state flow changes.

## Flashcard Zone Editor Guardrails

The flashcard zone editor is interaction-sensitive and can regress from small SwiftUI/UIKit changes. Treat bugs in `FlashcardEditorView`, `ZoneView`, `ZoneTextView`, zone resizing, cursor placement, selection, keyboard avoidance, or editor/play preview parity as a special local system.

`MUST` preserve these invariants:
- Tap on text places the caret; text selection starts only from native long press, drag handles, or double tap.
- Moving the caret must not change zone size, text wrapping, padding, alignment, or scroll position.
- Focus and unfocus must use identical text metrics. The focused `UITextView` and unfocused raw preview must not have different insets, line spacing, font, width, or vertical alignment.
- A newly created empty text zone must keep a stable minimum visual size after losing focus; it must not collapse to a one-line sliver.
- Resize handles, debug HUDs, selection outlines, toolbar overlays, and parent gestures must not steal `UITextView` touch handling.
- Per-caret or per-selection updates must not invalidate the whole card layout. Avoid using cursor changes to update observed state that recomputes sizes.
- Do not switch between rendered math/rich preview and raw editor metrics inside the editor unless the task explicitly reintroduces compiled preview behavior.

For zone editor bugs, start with the route in `references/task-routing.md` before opening broader DeckEditor files.

## Workflow

1. Identify the ownership layer first from the file path and local neighbors.
   - Keep `Domain/Models/` data-oriented.
   - Keep `Features/*/ViewModels/` focused on business logic and async orchestration.
   - Keep `Views/` and `Components/` focused on rendering and event forwarding.
2. Escalate references on demand, not by default.
   - Use `references/task-routing.md` for the smallest safe starting set.
   - Use `references/project-map.md` only when ownership, placement, or feature boundaries are unclear.
   - Use the specific sections of `references/architecture.md` that match the task, not an automatic full read for local UI or copy edits.
3. Follow the repository's data-access rules before changing SwiftData code.
   - Prefer denormalized counters over relationship `.count`.
   - Route heavy card-content reads through `CardFetchActor`.
   - Save mutations explicitly and surface failures.
4. Match the project's UI system before changing presentation code.
   - Use `UIConstants` tokens instead of magic numbers.
   - Prefer semantic colors and existing theme plumbing.
   - Prefer shared design-system modifiers and components such as `widgetStyle`, `glassButton`, shared rings, and existing chrome containers over ad-hoc overlays, borders, shadows, or custom surface treatments.
   - Keep navigation programmatic through `NavigationManager`.
   - Treat long scrolling surfaces and immersive modal flows as architecture-sensitive code paths, not local view tweaks.
   - On iPad and other resizable environments, derive layout from the container geometry and available width instead of `UIScreen` assumptions. Expect split view, Stage Manager, and future resizable iPad windows to expose widths that differ materially from full-screen iPad.
   - On drag-heavy or scroll-heavy surfaces, do not leave expensive collection-wide work in view `computed` properties.
   - If a value walks many cards, zones, diagnostics, or summaries, cache it in local state or move it out of the hot render path, then recompute only when the source collection actually changes.
   - Prefer `Equatable` row views and other diff-friendly techniques for large editor/deck lists so parent refreshes do not rebuild every row.
5. Preserve the repo's file hygiene when generating or rewriting files.
   - Keep Apple-style file headers.
   - Keep `// MARK: -` sections.
   - Keep DocC comments on new internal and public declarations.
   - Remove `TODO:`, `FIXME:`, and commented-out code from generated output.

## Debug Escalation

When repeated fixes do not change the user's observed behavior, stop guessing and add targeted instrumentation before making another behavioral change. Prefer DEBUG-only probes that reveal the exact owner of the failure: hit-test recipients, gesture recognizer state, state transitions, async cancellation, persistence writes, or payload shape. Keep probes narrowly scoped, easy to remove, and gated behind existing development/debug settings when practical. If the probe exposes a generally useful diagnostic path, keep it as a development-only tool; otherwise remove it before final delivery. In final reports, state what the instrumentation showed and which assumption it confirmed or disproved.

## Testing Expectations

1. Treat meaningful data-flow changes as testable by default.
   - When a change introduces new mutation logic, changes persistence semantics, or fixes a data-flow bug in persisted app data, add or update automated tests unless the user explicitly says not to.
   - Small UI plumbing changes that merely invoke an already-tested mutation path do not automatically require new tests.
2. Prefer logic and persistence tests over UI automation.
   - Use `XCTest` suites in `QuizFlashTests/` to validate models, view models, stores, import/export, and detached persistence flows.
   - Leave UI validation to manual verification unless the task explicitly asks for UI tests.
3. Use deterministic in-memory fixtures for SwiftData.
   - Prefer a dedicated in-memory `ModelContainer` test helper over production storage.
   - Seed relationships in the direction the production code actually reads (`deck.cards`, `deck.folder`, etc.) to avoid SwiftData registration traps.
4. Verify tests conservatively on one simulator at a time.
   - Prefer `build-for-testing` once, then `test-without-building` per suite or class.
   - Disable parallel testing for local verification unless the user explicitly wants parallel runs.
   - Prefer targeted `xcodebuild` test runs against the current workspace's default simulator instead of broad generic destinations.
   - If repo-local instructions such as `AGENTS.md` or an adapter file define a preferred simulator or attached device, follow those workspace-local verification defaults.
   - When the `ios-simulator` MCP is available, use it for post-build UI inspection on simulator flows that benefit from accessibility-tree validation, coordinate taps/swipes, text entry, screenshots, or screen recordings.
   - For layout-sensitive UI work, also do a manual visual pass on iPad-sized and resizable widths when the changed screen supports them, especially for sticky headers, compact calendar states, floating chrome, and multi-column/dashboard surfaces.
5. Extend the regression net when fixing a bug.
   - If a data-flow bug is discovered while testing, fix the fixture or production code at the root cause and keep the new test as a permanent guardrail.

## Decision Points

- The `Quick Start` section is the canonical context-loading rule for existing-file tasks.
- Inspect `references/project-map.md` before adding a new type only if you are not sure where it belongs.
- Read the relevant sections of `references/architecture.md` before touching navigation, concurrency, SwiftData, or performance-sensitive code.
- Read `references/architecture.md` end to end only for new features, large refactors, or reviews that cross multiple layers.
- Read the scroll and presentation guidance in `references/architecture.md` before changing any large `ScrollView`, sticky hero, floating top chrome, or custom full-screen presentation.
- Prefer the standards in this skill for new code. If a surrounding file still uses an older pattern, keep the change narrow unless the task explicitly asks for cleanup.

## References

- `references/task-routing.md`: Smallest safe starting points and escalation triggers for local tasks.
- `references/project-map.md`: Real repo layout, important files, and common starting points.
- `references/architecture.md`: Project rules for architecture, concurrency, SwiftData safety, navigation, design tokens, code style, and review checks.
- `references/examples/ViewModel.swift.example`: Canonical QuizFlash-flavored view-model skeleton for new code.
- `references/examples/View.swift.example`: Canonical QuizFlash-flavored root-view skeleton for new screens.
- `references/component-catalog.md`: Reusable UI inventory; check this before creating a new component.
- `references/antipatterns.md`: Concrete "before/after" guidance for patterns that still appear in older files.
- `references/new-feature-template.md`: End-to-end feature scaffold and implementation order.
- `references/universal_prompt.md`: Copy-paste prompt template for other agents/tools.

## Before Writing Any New Feature

For new screens or end-to-end features, deeper loading is expected than for local edits.

1. Read `references/project-map.md` to confirm the ownership layer and target folder.
2. Read `references/component-catalog.md` before creating any new card, row, toolbar, menu, overlay, or modal.
3. Read `references/architecture.md` before touching navigation, concurrency, SwiftData, scroll behavior, or design-system-sensitive UI.
4. Read `references/antipatterns.md` if the surrounding files are older or you need to avoid repeating legacy patterns.
5. Read `references/examples/ViewModel.swift.example` and `references/examples/View.swift.example` when starting a new screen or refactoring one toward the current architecture.
6. Read `references/new-feature-template.md` when building a feature end to end or wiring multiple new files together.

## Using This Skill With Other Agents

This skill is intentionally written to be mostly agent-agnostic:
- `SKILL.md` + `references/` are the *core* rules (architecture + repo conventions).
- `agents/*.yaml` are *adapters* (short, tool/platform-specific wrapper prompts).
- `references/universal_prompt.md` is a copy-paste prompt template you can reuse in other AI tools.

### What To Share With Another Agent

When you use Claude/ChatGPT/Cursor/etc. outside Codex, paste or attach first:
- `SKILL.md`
- `references/task-routing.md`

Add these only when the task needs them:
- `references/architecture.md`
- `references/project-map.md`
- `references/component-catalog.md`

If the agent cannot access your repo directly, also paste:
- the exact file paths involved
- the repro steps and expected behavior
- any console logs / screenshots

### Tool Capability Adaptation

- Agents *with* a terminal + repo access:
  ask for a patch (file edits) + a build (`xcodebuild`) verification.
- Agents *without* a terminal:
  require they propose changes with exact file + symbol targets and ask you to run `xcodebuild` and paste the failure output for iteration.

### Adapter Files

If you want this skill to show up in multiple agent runtimes, add more small adapter files:
- `agents/openai.yaml` (already present)
- `agents/anthropic.yaml` (Claude)
- `agents/cursor.yaml`
- `agents/generic.yaml`

Each adapter should keep the `default_prompt` short and reference this skill as the canonical source of truth.
