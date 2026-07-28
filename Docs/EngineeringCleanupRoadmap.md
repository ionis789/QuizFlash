# QuizFlash Engineering Cleanup Roadmap

Date: 2026-04-08

## Goal

- Aliniere la `quizflash-ios-engineer`
- Separare clară `development` vs `production`
- Reducere risc înainte de launch
- Curățare structurală fără rewrite mare

## Audit Snapshot

- App code: `213` Swift files, `73,443` LOC
- Tests: `29` files, `4,289` LOC
- Drift signals:
  - `ThemeManager.shared`: `93`
  - `UIScreen.main`: `15`
  - `DispatchQueue.main.async`: `21`
  - `DispatchQueue.main.asyncAfter`: `14`
  - `print(...)`: `49`
  - `DateFormatter(...)`: `25`
  - `@Query` inside `Features/*/Components/*`: `7`

## Biggest Files

1. `Services/AI/AIFlashcardService+GenerationPipeline.swift` — `1984`
2. `Core/DesignSystem/Components/CustomContextMenu.swift` — `1843`
3. `Features/DeckEditor/Views/AIGenerationSheetView.swift` — `1574`
4. `Services/AI/AIFlashcardService+Prompting.swift` — `1534`
5. `Features/DeckEditor/Components/AIWorkspaceViews.swift` — `1421`
6. `Features/Home/ViewModels/HomeDashboardCalculator.swift` — `1202`
7. `Domain/Models/CardModel.swift` — `1107`
8. `Features/PlayMode/FlashCardsMode/Components/SwipeableCard.swift` — `1050`
9. `Services/AI/AIFlashcardService+Networking.swift` — `1005`

## Confirmed Weak Points

### 1. Components still own data and fetch logic

This breaks the skill rule that `Components` should stay mostly render-only.

Examples:
- `Features/DeckDetails/Components/FolderDeckListView.swift`
- `Features/DeckEditor/Components/AIWorkspaceViews.swift`

Risk:
- hidden data ownership
- hard testing
- harder reuse
- unexpected refresh cost

### 2. Theme access is inconsistent

The skill wants environment-based theme access in new code. The repo still uses `ThemeManager.shared` heavily.

Examples:
- `Features/DeckEditor/Components/AIWorkspaceViews.swift`
- many Home / Library / DeckDetails / PlayMode files

Risk:
- mixed theme sources
- harder previews
- harder testing
- hidden global coupling

### 3. Layout still depends on `UIScreen.main`

This conflicts with the skill rule to derive layout from container geometry.

Examples:
- `Core/DesignSystem/Modifiers/View+FullScreenSheet.swift`
- `Features/DeckEditor/Components/CanvasModalView.swift`
- `Features/PlayMode/FlashCardsMode/Components/SwipeableCard.swift`
- `Core/DesignSystem/Components/CustomContextMenu.swift`

Risk:
- iPad / split view / Stage Manager regressions
- brittle overlays and sheets

### 4. Main-thread scheduling still uses legacy `DispatchQueue`

The skill prefers actor-aware and cancellation-aware flows.

Examples:
- `Core/Helpers/ScrollPositionRestorer.swift`
- `Core/DesignSystem/Modifiers/SwipeBackModifier.swift`
- `Features/DeckEditor/Components/MixedMathTextView.swift`
- `Features/PlayMode/FlashCardsMode/Components/SwipeableCard.swift`

Risk:
- race conditions
- timing bugs
- cancellation leaks
- harder reasoning

### 5. Logging is still ad-hoc

The repo still uses `print(...)` in production code paths.

Examples:
- `Services/Storage/DeckSharingManager.swift`
- `Services/AI/DocumentTextExtractor.swift`
- `Features/Home/ViewModels/HomeViewModel.swift`
- `Core/DesignSystem/Components/CustomContextMenu.swift`

Risk:
- noisy console
- weak filtering
- poor release diagnostics

### 6. Preferences and local persistence are too scattered

There is still direct `UserDefaults.standard` usage outside a single preference boundary.

Examples:
- `Core/Navigation/MainAppView.swift`
- `Core/DesignSystem/Theme/ThemeManager.swift`
- `Services/Auth/AuthManager.swift`
- `Services/AI/AIDebugTraceStore.swift`

Risk:
- duplicated keys
- migration drift
- harder testing

### 7. Dev tooling is routed better, but not fully isolated yet

The navigation cleanup started, but physical placement is still mixed.

Examples:
- `Features/Settings/Views/AIProviderSettingsView.swift`
- `Features/Settings/Views/AIDebugTraceHistoryView.swift`
- `Features/Settings/Views/LatexSymbolLabView.swift`

Risk:
- dev code still mixed with production settings
- release cleanup remains manual

### 8. Some file names and module placement still break repo hygiene

Examples:
- `Features/Folder/Views/Folderview.swift`
- `Features/Home/Views/Homedashboardview.swift`

Risk:
- weaker discoverability
- harder search
- inconsistent conventions

### 9. Large files still mix multiple responsibilities

Main hotspots:
- AI pipeline files
- `CustomContextMenu`
- `AIGenerationSheetView`
- `AIWorkspaceViews`
- `SwipeableCard`

Risk:
- slower edits
- higher regression surface
- review fatigue
- hidden coupling

### 10. Test coverage is good in core data flows, but still thin on shell and infra

Gaps:
- build gating
- labs visibility
- development tooling routing
- context menu behavior
- layout calculators for compact cards / overlays

Risk:
- launch regressions in shell behavior
- fragile UI infrastructure changes

## Release-Critical Work

These items should be done before launch.

### Phase 0. Lock the app boundary

Scope:
- define what must not ship in `Release`
- make dev tooling removable by configuration, not manual cleanup

Deliverables:
- add `AppFeatures`
- gate debug overlays and AI trace tooling from one place
- remove development-only tabs, routes, and production-facing entry points

Exit:
- user navigation contains no development-only destinations
- visual debug toggles are unavailable in `Release`

### Phase 1. Remove development-only UI

Scope:
- remove development-only screens and routes from the user application
- keep only user-facing settings in `Settings`

Deliverables:
- remove Feature Lab screens, routes, resources, and Settings entry points
- keep production-used diagnostics behind build-flavor gates

Exit:
- `Features/Settings` contains only production settings
- no developer navigation exists in the user application
- production settings have no dependency on developer tooling

### Phase 2. Replace risky infra patterns still touching launch paths

Scope:
- prioritize high-traffic screens and shared infra

Deliverables:
- remove `UIScreen.main` usage from:
  - `View+FullScreenSheet`
  - `CustomContextMenu`
  - `SwipeableCard`
  - `CanvasModalView`
- replace `DispatchQueue.main.async*` in scroll / sheet / gesture-sensitive flows
- convert production `print(...)` to `Logger`

Exit:
- critical shared infra uses geometry / actor-safe sequencing / structured logging

### Phase 3. Fix component ownership violations in hot UI

Scope:
- remove `@Query` and fetch logic from components used in active surfaces

Deliverables:
- refactor `FolderDeckListView`
- refactor `AIWorkspaceViews`
- move fetches into root views or view models

Exit:
- shared components receive data via inputs
- no new `@Query` inside `Components`

## Post-Launch Structural Work

### Phase 4. Theme and design-system alignment

Scope:
- remove global theme reads from new-path screens

Deliverables:
- replace `ThemeManager.shared` with environment access in touched features
- standardize shared surfaces, color reads, and semantic tokens

Priority files:
- `AIWorkspaceViews`
- `DeckCardGridView`
- `LibraryDeckListRow`
- `SwipeableCard`

Exit:
- no new `ThemeManager.shared`
- shared UI reads theme through environment by default

### Phase 5. Split oversized files

Scope:
- break large files by ownership, not arbitrary sections

Order:
1. `CustomContextMenu.swift`
2. `AIWorkspaceViews.swift`
3. `AIGenerationSheetView.swift`
4. `SwipeableCard.swift`
5. `AIFlashcardService+GenerationPipeline.swift`

Split targets:
- state / coordinator
- layout calculator
- menu surface
- diagnostics / logging
- networking / prompting / parsing helpers

Exit:
- no UI file over ~`900-1000` LOC unless justified
- shared infra is split into testable helpers

### Phase 6. Preferences, migrations, and storage cleanup

Scope:
- centralize local settings and transient flags

Deliverables:
- move dev toggles out of `AppPreferences` into `DevelopmentPreferences`
- wrap remaining `UserDefaults.standard`
- centralize keys and migrations

Exit:
- app-wide defaults go through explicit stores
- no scattered raw keys in features

### Phase 7. Formatting and utility cleanup

Scope:
- remove low-grade drift and repeated utility work

Deliverables:
- replace inline `DateFormatter()` with static formatters
- rename inconsistent files
- remove remaining low-value legacy helpers if redundant

Exit:
- no hot-path formatter allocation
- naming follows repo conventions

### Phase 8. Test hardening

Scope:
- add tests for infra and shell gaps

Add tests for:
- build-flavor gating
- user-facing tab inventory
- `MiniCardPreviewLayoutCalculator`
- `CustomContextMenu` layout and dismiss decisions
- settings / preferences migration paths

Exit:
- shell and infra changes have regression coverage

## Recommended Execution Order

1. Phase 0
2. Phase 1
3. Phase 2
4. Phase 3
5. Release
6. Phase 4
7. Phase 5
8. Phase 6
9. Phase 7
10. Phase 8

## Rules During Cleanup

- no big-bang rewrite
- no new `@Query` in components
- no new `ThemeManager.shared` in feature code
- no new `UIScreen.main` for layout
- no new `DispatchQueue.main.async*` without a strong reason
- no dev-only entry points in production navigation
- every refactor in shared infra gets targeted verification

## Suggested First PR Stack

### PR 1

- add `AppFeatures`
- finish `development` vs `production` gating
- remove remaining production links to dev screens

### PR 2

- remove obsolete development-only views and preferences
- clean `Settings`

### PR 3

- remove `UIScreen.main` and `DispatchQueue.main.async*` from shared infra hot paths
- convert production `print(...)` to `Logger`

### PR 4

- remove `@Query` from components in `DeckDetails` and `DeckEditor`

### PR 5

- split `CustomContextMenu`
- add tests for layout / routing gates

## Success State

- `Release` is clean by configuration, not by manual cleanup
- `Settings` contains only user-facing settings
- developer UI is absent from the user application
- retained diagnostics are build-flavor gated
- shared components are render-only
- shared infra is geometry-based and actor-safe
- theme access is consistent
- large files are split by responsibility
- shell and infra regressions are covered by tests
