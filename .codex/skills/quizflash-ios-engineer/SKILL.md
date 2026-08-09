---
name: quizflash-ios-engineer
description: Project-specific engineering guide for QuizFlash, a SwiftUI flashcard app targeting iOS 17+ with Swift 6, SwiftData, Firebase Auth/Firestore, a Cloudflare transparent DeepSeek proxy, and a future RevenueCat subscription integration. Use when Codex writes, reviews, debugs, or refactors code in this repository, especially for SwiftUI, SwiftData, Firebase/backend security, AI prompts, quotas, provider transport, subscription/paywall work, navigation, performance, editor/play rendering, or when the user requests advanced debugging, detailed diagnostics, construction flow, event flow, or tester-provided debug output.
---

# QuizFlash iOS Engineer

## Overview

Create and review code for QuizFlash using the repository's architecture rules instead of generic SwiftUI defaults. Optimize for the smallest safe context: start from the target file, load the paired owner file next, and pull longer references only when the task actually crosses those boundaries. Treat the standards in `references/architecture.md` as the target for new code even when older files still contain legacy patterns.

When the user sends screenshots, treat them as direct QuizFlash app evidence unless they explicitly say otherwise. First identify which app screen/surface is shown from visible UI, navigation chrome, labels, tabs, cards, or controls, then map the issue to the smallest likely owner file before editing. The user often draws red callouts with text boxes and pointer tails directly on screenshots; interpret those annotations as the primary problem statement and infer the intended correction from where each pointer lands. Do not treat the red annotation boxes as app UI. If a screenshot is ambiguous, use `rg` on visible labels/symbols to locate the owning screen, and ask a question only when the screen or intended target still cannot be identified safely.

QuizFlash no longer ships an exam-goals feature on Home. Treat `Home` as a study dashboard focused on calendar activity, recent decks, folders, and performance summaries. Do not introduce or preserve `ExamGoalModel`, exam-goal sheets, exam readiness widgets, or calendar exam markers unless the user explicitly asks to reintroduce that product area.

Keep UI copy terse. Do not add explanatory filler, repeated titles, helper paragraphs, or decorative subtitles unless they are necessary for the screen to function. Default to the minimum viable copy on primary surfaces: if a label, subtitle, helper line, or decorative text can be removed without harming clarity, remove it. This applies especially to development/internal screens and settings surfaces.

For production UI components, `MUST NOT` add descriptions for obvious controls or settings such as Language, Calendar, Navigation, Logout, Delete, Done, Select, or similar self-explanatory actions. A clear label plus the control value/icon is enough. Add supporting copy only when the user needs it to avoid data loss, understand an irreversible/destructive consequence, or disambiguate a genuinely complex choice.

QuizFlash now ships multi-language UI and all new app-owned copy must be localization-ready. The supported UI languages are English (`en`), Romanian (`ro`), and Russian (`ru`). Do not hardcode user-facing app copy behind plain runtime `String` properties when that would bypass localization; prefer `LocalizedStringResource`, existing localized helper methods that accept `Locale`, or explicit prelocalized strings when runtime values must cross navigation/state boundaries. When adding or changing app-owned copy, update every supported language, not just English. User-authored content such as deck titles, folder names, and card text must remain verbatim and must not be routed through app-string localization.

QuizFlash uses an app-language bundle override, not just SwiftUI environment locale, to resolve localized strings. Do not assume `locale` alone will switch the lookup language for `String(localized:)` or other bundle-backed copy. For app-owned UI copy, prefer `AppLocalization.string(...)` / `AppLocalization.numbered(...)` over direct `String(localized: ..., locale: ...)`; the direct form has already caused real regressions where dates localized correctly but UI copy stayed in English. If localization infrastructure changes, keep `AppLocalization.applyLanguageOverride(...)` wired so bundle lookup and date/number formatting stay in sync. For quick vocabulary edits across all supported languages, keep `Docs/UI-Dictionary/localization_matrix.py` working: it exports and imports the shared `key / en / ro / ru` table used for review and bulk editing.

Treat `Docs/UI-Dictionary/localization_matrix.tsv` as the human-editable source of truth for app-owned UI vocabulary review. When adding, changing, or removing app-owned copy, update the underlying localization keys for all supported languages and keep the matrix in sync in the same task. Do not leave new copy only in `.strings` files without regenerating the matrix, and do not remove copy from code while leaving stale keys behind in the matrix unless the task explicitly preserves them for later reuse. The default workflow is: edit code + localized values, then run the matrix export/import flow so reviewers can inspect wording from one table instead of diffing raw `.strings` files.

Preserve layout stability on dynamic scroll surfaces. When selected dates, filters, live counters, or other in-place state changes can swap text or metrics inside a scrolling screen, reserve stable heights for the affected slots so the surrounding card or section does not jump and disturb scroll position. Avoid springy or bouncy text motion for these changing values unless the user explicitly asks for that treatment.

Treat animation smoothness as a first-class product requirement. For visible transitions, avoid mounting expensive SwiftUI subtrees, recomputing large layouts, observing per-frame geometry, or triggering persistence/async work on the same state edge that starts the animation. Prefer animating cheap layer-friendly properties such as opacity, scale, and transform on already-mounted views; keep keyboard, scroll, and toolbar animations isolated so they do not invalidate each other.

Treat keyboard-safe custom sheets as one shared application contract. Any `fullScreenSheet` that contains `TextField`, `SecureField`, `TextEditor`, or another text input `MUST` enable the shared keyboard-avoidance path and host form content in `KeyboardAdaptiveSheetContent`; do not reproduce local keyboard offsets, competing height animations, one-off clipping masks, or non-scrollable form stacks. During keyboard presentation and dismissal, interactive content must remain fully inside the visible rounded sheet surface on every animation frame, not only in the final layout. Keep the hosted content and its clipping surface on one animation transaction, preserve enough top clearance for rounded corners, and use size-based scrolling so smaller devices, Dynamic Type, password suggestions, and alternate keyboards cannot hide controls. Sheet resizing caused by keyboard appearance or dismissal `MUST` use the same fixed `FullScreenSheetMotion` timing and curve as sheet presentation and dismissal; never substitute the variable duration reported by the system keyboard. When changing any text-input sheet, compare it with the authentication sheet and verify both keyboard show and hide transitions.

Treat custom-sheet presentation motion as one non-configurable application contract. Every app-owned surface that behaves like a sheet `MUST` use `fullScreenSheet`; do not introduce SwiftUI `.sheet` for app-owned forms or content. Opening and closing use the shared `0.28 s` smooth, zero-bounce motion from `FullScreenSheetMotion`, with one symmetric travel distance and teardown derived from that same duration. Call sites may configure height, chrome, blur, drag activation, keyboard avoidance, and tab-bar behavior, but `MUST NOT` override presentation timing or add competing transitions. Native iOS service presenters such as activity/share and document pickers may keep their system presentation. Card authoring, image crop, and drawing canvases are full-screen workflows and remain outside the sheet contract unless the product explicitly changes their navigation model.

After every code modification, commit the finished change before handing control back. Use a very short commit message, ideally only a few words and at most one concise sentence, describing what changed.

QuizFlash is pre-release and has no production users. `MUST NOT` add backward-compatibility branches, legacy decoding defaults, dual contract support, deprecated aliases, fallback behavior for superseded app/backend versions, or other dead code unless the user explicitly requests compatibility for a specific artifact. When changing an internal contract, update every current caller, test, prompt bundle, and backend counterpart in the same task, then remove the superseded path. Existing keys or code that the current app still executes are not legacy merely because they predate the change.

## Local Machine Performance Guardrails

Protect the user's laptop performance as a hard requirement. `MUST NOT` run broad, expensive, or unrelated commands just because they are available. Match verification scope to the task: for UI-only work, do not trigger backend builds, cloud deploys, package resolution, clean builds, or full dependency rebuilds unless the user explicitly asks for that level of verification.

Routine iOS verification `MUST` reuse Xcode's existing incremental `DerivedData` and Swift Package caches. Omit `-derivedDataPath` for normal builds, do not create a fresh build cache, and do not delete/reset package artifacts merely to obtain a clean build. Do not run `xcodebuild -list` or `-resolvePackageDependencies` when the project and scheme are already known. Use the same scheme and destination with `-skipPackageUpdates` and `-disableAutomaticPackageResolution` when the existing cache supports them so Firebase, Google Sign-In, Lottie, and other unchanged dependencies are not rebuilt. If Xcode proves that a dependency cache is missing, corrupt, or incompatible, stop and explain the evidence and expected cost before authorizing any package re-resolution or dependency rebuild.

An incremental QuizFlash build is expected to begin producing real compile output within seconds. If `xcodebuild` produces no meaningful progress for 15 seconds, repeatedly invokes setup tools such as `actool --version`, starts recreating Swift Package working copies, or causes sustained abnormal CPU usage, interrupt it immediately. `MUST NOT` retry a stuck build with a new `DerivedData` path, a clean build, a second concurrent build, or fresh package working copies. Report the hang and wait for explicit user approval before any more expensive verification. After interruption, verify that task-owned Xcode/package child processes are gone before doing anything else.

`MUST NOT` put Xcode `DerivedData`, build products, package caches, simulator artifacts, logs, or generated dependency output inside the repository. Never use `-derivedDataPath build/DerivedData`, `DerivedData`, `.build`, or any repo-relative path for Xcode build output. If a custom path is unavoidable, use a temporary path outside the repo and clean it up only when no related process is running.

`MUST NOT` run `git add -A`, `git add .`, or any broad staging command in this repo. Stage only the exact files intentionally changed by the task. Before staging, make sure generated folders such as `build/`, `DerivedData/`, `.build/`, package caches, simulator output, and logs are not inside the working tree or included by the command.

`MUST` avoid commands that recursively walk huge generated trees unless they are strictly necessary. Do not run broad `du`, `find`, `ls -R`, `git diff`, `git status --ignored`, or repository-wide scans over build artifacts. Use targeted `rg --files`, `rg`, `sed`, and file-specific `git diff -- path` reads instead.

Before starting a command expected to run for more than roughly 30 seconds, `MUST` state what will run and why. For heavy verification, prefer the already-open simulator/device and the smallest relevant command. Do not boot hidden simulators, start long recordings, or keep Device Hub recordings running as a side effect of verification.

After interrupting or finishing any heavy command, `MUST` check for leftover `xcodebuild`, `swiftc`, `clang`, `SWBBuildService`, runaway `git add`, simulator recording, or indexing processes related to the task, and stop only those task-owned leftovers before handing control back. If a process is stuck in uninterruptible I/O at `0% CPU`, report it clearly instead of repeatedly spawning more cleanup commands.

Treat data-heavy render paths as a known QuizFlash failure mode. The Home performance incident showed that computed properties and `.task(id:)` signatures that walk SwiftData arrays can create severe CPU and allocation churn during scroll, even when there is no classic retain-cycle leak. On any screen with many decks, cards, zones, logs, aggregates, diagnostics, or summaries, do not calculate fingerprints, filters, sorts, grouped summaries, relationship counts, calendar/date formatting, or model projections inside `body` or other render-time computed properties. Cache snapshots or signatures in `@State`, a `@MainActor` view model, or a background actor, and invalidate them from cheap change signals only when source data actually changes.

When animation or interaction lag survives an initial optimization, lead with an explicit debugging protocol instead of passively waiting for another symptom report. Add narrowly scoped DEBUG-only visual instrumentation when useful, tell the user exactly what gesture/video to capture, and explain which metrics will confirm or reject the current hypothesis.

Golden debug rule: after any failed behavioral fix, or whenever more than one plausible root cause remains, `MUST NOT` make another behavioral fix from inference alone. Stop, say explicitly that the current evidence is insufficient for a safe fix, and add or request deterministic diagnostics that will identify the owning layer before changing behavior again. For UI/interaction bugs this means instrumenting the actual event/state path (hit testing, gesture recognizers, focus, keyboard, presentation flags, layout frames, async tasks, persistence writes as relevant), then using the resulting log/video/screenshot to choose exactly one fix.

Treat the user's phrases `debug avansat`, `debug detaliat`, `flow complet`, `construction flow`, or equivalent as an explicit protocol request. `MUST` read `references/advanced-debugging.md` before editing behavior. Build a persistent, exportable timeline that records inputs, ownership boundaries, state transitions, measurements, invalidations, fallbacks, acceptance/rejection decisions, and final applied values. A final-state snapshot alone is insufficient. The user acts as the runtime tester: provide a precise reproduction request, receive the exported output, compare failing and working paths, and patch only the layer proven by the trace.

For serious lag, global scroll stutter, slider jank, memory growth, or suspected leaks, use Instruments instead of guessing. Ask for or analyze a `.trace` with Time Profiler + Allocations, inspect the TOC because one trace can contain multiple runs, prioritize app-inclusive stacks and allocation churn, then fix the hot render/data path. Read `references/performance-profiling.md` before giving profiling instructions or interpreting a trace.

Do not route per-frame scroll offsets through observed SwiftUI state. Persist scroll restoration offsets in `@ObservationIgnored` view-model storage or other non-observed holders so scroll probes do not invalidate an entire screen on every drag tick.

On iOS 17, do not reconfigure live blur/filter layers during scroll-driven updates. If a root surface needs a top progressive blur, keep the `UIViewRepresentable` stable and mutate only cheap scalar inputs such as opacity or an already-attached radius value. Avoid calling layer/filter refresh code from `updateUIView` on every drag tick; use a static fallback only when a stable live path is not available.

Treat iOS 17.5 as the strict compatibility baseline for SwiftUI/UIKit presentation behavior. Do not assume behavior that works on iOS 18, iOS 26, or a physical newer-OS device is valid on iOS 17. Be especially conservative around `UIViewRepresentable` / `UIViewControllerRepresentable` hosted inside SwiftUI containers, custom sheets, masks/clips, `.compositingGroup()`, material/blur surfaces, gesture recognizers, and overlays. On iOS 17 these combinations can render correctly while hit-testing, scroll interaction, or gesture delivery is broken. When masking interactive hosted content, prefer UIKit-level clipping on the hosted view/controller or clip only non-interactive visual layers; avoid wrapping the whole interactive host in SwiftUI compositing + clip unless it has been verified on iOS 17.5.

Use the current DeckEditor naming. `CardEditorView` is the router from `CardEditorDestination` into concrete editor surfaces. `FlashcardEditorView` owns the zone-based front/back flashcard editor, and `QuizCardEditorView` owns quiz authoring. Supported card creation and generation flows are limited to flashcards and quizzes unless the user explicitly asks to restore archived product areas.

QuizFlash uses SwiftData as the local runtime store and a canonical `.json` deck document as the external contract for export/import, backend sync, and AI card payloads. Keep those layers separate: do not make SwiftData models conform to API shape directly, and do not let AI generate deck metadata, IDs, dates, counters, or persistence state. AI generation should return only the shared card DTO for supported Flashcard/Quiz content; the app validates that DTO, maps it to `DraftCardContent`, then creates or updates `CardModel` instances.

QuizFlash now has a Firebase backend. Treat Firebase Auth, Firestore rules, Cloud Functions, DeepSeek usage, and future RevenueCat entitlement sync as one security boundary, not unrelated features. Before changing user profiles, cloud sync, AI generation, quota/plan logic, provider keys, purchases, or Firestore rules, `MUST` read `references/backend-integrations.md` and follow its current-state notes and rollout order. The backend must be the authority for paid access, quotas, and provider secrets; a SwiftUI check, a Firestore field writable by a client, or a local AI-provider profile is never sufficient production enforcement.

QuizFlash production AI uses the `quizflash-ai` Cloudflare Worker as a transparent DeepSeek proxy. Before changing AI prompting, the proxy, quota, or provider transport, `MUST` also read `references/ai-proxy.md`. Keep the release pipeline invariant: iOS owns the generation planner, dynamic request composition, title generation, retries, DTO decoding, LaTeX normalization, and local card insertion; the Worker owns Firebase authentication, entitlement/quota/cost enforcement, the DeepSeek secret, and raw request/response forwarding. Do not move prompt composition, JSON repair, title parsing, DTO mapping, or response rewriting into the Worker.

Prompt text is being moved to backend-owned versioned configuration, not backend-generated requests. When that work is implemented, iOS must compose the exact existing messages from server-delivered text templates and its existing dynamic values. Reuse the already-required generation `start` request and a persistent versioned cache so prompt retrieval does not add a new blocking round trip before a provider request. A remote prompt configuration controls quality and iteration speed, but is not a security boundary: a transparent proxy cannot prove a client used an unmodified prompt body.

`MUST NOT` hardcode lexical word lists, language vocabularies, subject keyword lists, or prompt-like classifier terms in Swift, Worker code, or prompt assembly logic to infer source language, subject domain, deck title, or content category. For automatic language/title/profile decisions, use one AI preflight from versioned prompt templates or an explicit user/admin setting, then propagate that single resolved result to every batch in the generation run. The client may validate response shape and normalize generic codes, but must not decide language or topic from local vocabulary markers.

QuizFlash AI generation exposes only two depth profiles: Simple and Pro. Keep Simple concise but still useful and testable; keep Pro deeper and more structured without turning cards into essays. Prompting should adapt to the source domain: math/formal subjects should be formula-first with concise interpretation, while history, literature, biology, law, and other prose-heavy subjects should use segmented natural-language explanation. Prefer several small semantic zones over dense answer paragraphs. When editing generation prompts, avoid hardcoding supported UI languages or arbitrary numeric layout thresholds. Phrase guidance in terms of the source/output language, semantic content, and the actual JSON/schema constraints; use fixed numbers only when the product contract truly requires them.

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
   - Firebase/Auth/Firestore/Functions, DeepSeek, quotas, paywalls, purchases, or RevenueCat: read `references/backend-integrations.md` first
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
   - If the same symptom has already resisted one fix, or if two or more root causes are still plausible, switch to targeted instrumentation before more behavioral changes.
   - If a user-provided video, screenshot, log, or trace does not prove the owning layer, say that directly and ask for or add the missing deterministic signal instead of guessing.
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

The flashzone content editor is interaction-sensitive and can regress from small SwiftUI/UIKit changes. Treat bugs in `FlashcardEditorView`, `ZoneView`, `ZoneTextView`, zone resizing, cursor placement, selection, keyboard avoidance, or editor/play preview parity as a special local system.

`MUST` preserve these invariants:
- Tap on text places the caret; text selection starts only from native long press, drag handles, or double tap.
- Moving the caret must not change zone size, text wrapping, padding, alignment, or scroll position.
- Focus and unfocus must use identical text metrics. The focused `UITextView` and unfocused raw preview must not have different insets, line spacing, font, width, or vertical alignment.
- A newly created empty text zone must keep a stable minimum visual size after losing focus; it must not collapse to a one-line sliver.
- Resize handles, debug HUDs, selection outlines, toolbar overlays, and parent gestures must not steal `UITextView` touch handling.
- Per-caret or per-selection updates must not invalidate the whole content layout. Avoid using cursor changes to update observed state that recomputes sizes.
- Do not switch between rendered math/rich preview and raw editor metrics inside the editor unless the task explicitly reintroduces compiled preview behavior.
- After one failed fix in this editor, or whenever tap/focus/menu/keyboard behavior could be owned by multiple layers, do not patch behavior again until DEBUG-only instrumentation proves which layer is responsible. Required signals usually include: tap coordinate and recipient, selected path, focused zone ID, pending focus ID, `UITextView` first-responder state, keyboard visibility/height, toolbar presentation flags, relevant frames, and any gesture/hit-test blockers.

For zone editor bugs, start with the route in `references/task-routing.md` before opening broader DeckEditor files.

## Flashcard Rich Content Overflow

QuizFlash flashcards and quiz cards use the same rich content renderer for mixed text, KaTeX math, inline code, and code blocks. Preserve the current local-overflow model when changing these surfaces:

- `MUST` make only the overflowing atomic content scroll horizontally: `.katex-display`, inline KaTeX wrappers, inline code wrappers, or code-block scroll views. Do not make the whole text block, card, or `#content` globally horizontally scrollable.
- `MUST` base overflow decisions on real post-render layout measurements, including child visual bounds when parent bounds underreport KaTeX/code width. Hardcoded formulas, words, domains, or text patterns are not acceptable.
- `MUST` keep normal prose wrapping normally around scrollable atomic content. Long inline formulas/code may move into their own full-width scroll wrapper when needed, but nearby text must not become part of that scroll region.
- `MUST` preserve smart gesture handoff in Play Mode and quiz play surfaces: local horizontal scroll handles the pan while it can move; at the horizontal edge in the drag direction, the card swipe gets the gesture. Taps outside an active scroll region must still flip/select as the parent card expects.
- `MUST` keep gesture ownership single-source across SwiftUI/UIKit/WebKit. The parent Swift/UIKit surface owns card-level actions and animation state such as flip/select/swipe; the WebView/KaTeX bridge should emit only events the parent cannot receive because WebKit owns hit-testing for an interactive overflow region. Do not add parallel `.onTapGesture` handlers on parent scroll/content wrappers when a WebView bridge can also emit the same tap.
- `MUST` fix WebView/KaTeX tap bugs by removing duplicate gesture paths at the source, not by debouncing state mutations after multiple callbacks fire. If a tap is received twice, identify which SwiftUI/UIKit/JS recognizers emitted it and make exactly one layer responsible for that touch path.
- `SHOULD` model rich-content tap routing explicitly when sharing the grid renderer across flashcards and quiz choices. For example, flashcard playback can let the outer card handle normal taps while allowing only rich/WebView leaves to forward a tap; quiz choices may intentionally allow all leaf taps because selection is owned by the answer row.
- `MUST NOT` set a delegate on `UIScrollView.panGestureRecognizer`; UIKit requires the built-in pan recognizer's delegate to remain its scroll view.
- `SHOULD` keep DEBUG diagnostics reporting the concrete scrollable regions, indicator state, and gesture handoff decision when changing this behavior.

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
4. Follow the backend contract before changing cloud or billing code.
   - Read `references/backend-integrations.md` before editing `firestore.rules`, `functions/`, `Services/Cloud/`, `Services/Subscriptions/`, `Services/Auth/`, AI-provider security, or purchase/entitlement code.
   - Keep Firebase UID as the stable cross-system user identity. Do not introduce email as a key or duplicate account identity.
   - Enforce plan, quota, and DeepSeek spend on the server. Keep client logic for presentation and preflight only.
   - Do not put provider keys, Firebase admin credentials, RevenueCat secret keys, webhook secrets, receipts, or CLI tokens in source, `UserDefaults`, Firestore, logs, screenshots, or chat output.
5. Follow the project's UI system before changing presentation code.
   - Use `UIConstants` tokens instead of magic numbers.
   - Prefer semantic colors and existing theme plumbing.
   - Prefer shared design-system modifiers and components such as `widgetStyle`, `glassButton`, shared rings, and existing chrome containers over ad-hoc overlays, borders, shadows, or custom surface treatments.
   - Keep navigation programmatic through `NavigationManager`.
   - Treat long scrolling surfaces and immersive modal flows as architecture-sensitive code paths, not local view tweaks.
   - On iPad and other resizable environments, derive layout from the container geometry and available width instead of `UIScreen` assumptions. Expect split view, Stage Manager, and future resizable iPad windows to expose widths that differ materially from full-screen iPad.
   - On drag-heavy or scroll-heavy surfaces, do not leave expensive collection-wide work in view `computed` properties.
   - If a value walks many cards, zones, diagnostics, or summaries, cache it in local state or move it out of the hot render path, then recompute only when the source collection actually changes.
   - When `.task(id:)` needs to react to large SwiftData query results, do not build the id by hashing every model property in `body`. Use a cached revision/snapshot updated from cheap count/id/profile signals, then run the heavy fingerprint only off the scroll render path.
   - Prefer `Equatable` row views and other diff-friendly techniques for large editor/deck lists so parent refreshes do not rebuild every row.
6. Preserve the repo's file hygiene when generating or rewriting files.
   - Keep Apple-style file headers.
   - Keep `// MARK: -` sections.
   - Keep DocC comments on new internal and public declarations.
   - Remove `TODO:`, `FIXME:`, and commented-out code from generated output.

## Debug Escalation

When a fix does not change the user's observed behavior, stop guessing immediately. Do not attempt a second behavioral fix unless the new evidence proves a single root cause. Read and follow `references/advanced-debugging.md`. Prefer DEBUG-only probes that reveal the exact owner of the failure: hit-test recipients, gesture recognizer state, focus/keyboard transitions, presentation flags, layout frames, state mutations, measurement acceptance, invalidation/reset causes, async cancellation, persistence writes, or payload shape. Keep probes narrowly scoped, easy to remove, and gated behind existing development/debug settings when practical. If the probe exposes a generally useful diagnostic path, keep it as a development-only tool; otherwise remove it before final delivery.

For every debug escalation, state the decision rule before asking for a video or making the next patch: what exact signal will confirm each plausible cause, and which code path will be changed for each outcome. Instrument the complete lifecycle, not only the suspected endpoint. Preserve a bounded event history before the debug panel is opened so initialization failures are not lost. Compare one failing instance with one working sibling under the same inputs. If a video/log is inconclusive, say so plainly and request or add the missing signal. In final reports, state what the instrumentation showed, which layer owned the defect, and which assumptions were disproved.

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

## App Run Verification

After any app code change, `MUST` do a real `build + run` verification before handing control back unless the user explicitly says not to. Prefer a connected physical iPhone first. If no usable physical device is connected, use the simulator that is already active in macOS 27 Device Hub. Treat Device Hub as the simulator control surface on macOS 27; do not assume the old standalone `Simulator.app` exists.

Do not boot a hidden/headless simulator as a fallback when Device Hub has no active simulator unless the user explicitly asks for that. If a task requires a fresh simulator and the user has not selected one, ask them to open/select it in Device Hub or state that run verification is blocked. Never leave a simulator booted only by Codex after verification; if Codex started it, shut it down before the final response.

## Decision Points

- The `Quick Start` section is the canonical context-loading rule for existing-file tasks.
- Inspect `references/project-map.md` before adding a new type only if you are not sure where it belongs.
- Read the relevant sections of `references/architecture.md` before touching navigation, concurrency, SwiftData, or performance-sensitive code.
- Read `references/backend-integrations.md` before touching Firebase, DeepSeek, AI quotas, RevenueCat, purchases, subscription state, or Firestore rules.
- Read `references/architecture.md` end to end only for new features, large refactors, or reviews that cross multiple layers.
- Read the scroll and presentation guidance in `references/architecture.md` before changing any large `ScrollView`, sticky hero, floating top chrome, or custom full-screen presentation.
- Prefer the standards in this skill for new code. If a surrounding file still uses an older pattern, keep the change narrow unless the task explicitly asks for cleanup.

## References

- `references/task-routing.md`: Smallest safe starting points and escalation triggers for local tasks.
- `references/project-map.md`: Real repo layout, important files, and common starting points.
- `references/architecture.md`: Project rules for architecture, concurrency, SwiftData safety, navigation, design tokens, code style, and review checks.
- `references/performance-profiling.md`: Instruments capture/export/interpretation protocol for Time Profiler, Allocations, hangs, and QuizFlash hot-path fixes.
- `references/advanced-debugging.md`: Mandatory deterministic instrumentation and tester-collaboration protocol for hard or repeatedly failing bugs.
- `references/backend-integrations.md`: Firebase ownership, Firestore security, Cloud Functions/DeepSeek limits, and RevenueCat rollout rules. Read before backend, AI quota, or subscription changes.
- `references/ai-proxy.md`: Live Cloudflare Worker topology, iOS transport contract, prompt-configuration migration rules, and deployment verification. Read before DeepSeek transport, prompt, or quota changes.
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
