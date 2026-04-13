# QuizFlash Top Edge Shadow Layering Refactor Plan

Date: 2026-04-14

## Goal

Refactor the top edge shadow so it behaves like a production-grade chrome effect:

- the shadow darkens only the screen background / scroll content
- floating top chrome stays above the shadow
- the solution is shared and controlled, not patched per button or per subview
- bottom edge shadow remains removed everywhere

## Current Problem

The current top shadow is rendered globally in:

- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/Navigation/MainAppView.swift`

That placement is structurally wrong for the effect we want.

Because the overlay is drawn in the root shell after `rootTabView`, it sits above all descendant screen content, including:

- floating top bars
- sticky chrome
- compact headers
- any view that should visually sit above the background fade

This creates an unavoidable z-order conflict:

- the shadow correctly covers background content
- but it also incorrectly darkens top-layer UI

This cannot be solved cleanly by adding more `zIndex` to child views, because descendants inside `rootTabView` cannot generally out-layer a parent overlay in a predictable, shared way.

## Decision

Do not keep the top edge shadow in the global app shell.

Instead:

1. Remove the structural top shadow from `MainAppView`.
2. Introduce a shared screen-level top-edge-shadow primitive.
3. Apply that primitive at the root layout level of each screen family.
4. Keep top chrome outside that primitive so chrome naturally layers above it.

This gives us explicit control over layering without one-off fixes.

## Correct Layering Model

Every screen that needs the shadow should follow this structure:

```swift
ZStack {
    background
    content
    EdgeShadowOverlay(topHeight: ...)
}
.safeAreaInset(edge: .top) {
    topChrome
}
```

Meaning:

- `background` sits at the bottom
- `content` scrolls above the background
- `EdgeShadowOverlay` darkens only those layers
- `topChrome` is injected after that, so it stays visually above the shadow

## Why This Is Correct

This matches how premium apps usually build immersive top chrome:

- the fade belongs to the content surface, not to the app shell
- chrome is composed later, not darkened retroactively
- each root screen owns its own top visual treatment
- behavior stays reusable because the pattern is shared at the layout boundary

This is not a per-view hack. It is a per-root-layout contract.

## Shared Primitive To Introduce

Create a shared modifier or container, for example:

- `ScreenTopEdgeShadowModifier`
- or `ScreenEdgeShadowContainer`

Responsibilities:

- wrap a screen background + content
- render top shadow with a configurable height
- optionally support transient fullscreen dim/fill when a screen needs it
- never render bottom shadow

Recommended API shape:

```swift
content
    .screenTopEdgeShadow(topHeight: ...)
```

or

```swift
ScreenEdgeShadowContainer(
    topHeight: ...
) {
    content
}
```

## Scope Of Migration

Apply the new pattern to root layouts, not to leaf views.

Primary migration targets:

- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Features/Library/Components/LibraryLayout.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Features/Home/Views/HomeView.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Features/DeckDetails/Views/DeckView.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Features/DeckEditor/Views/DeckWorkspaceView.swift`
- `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Features/Settings/Views/SettingsView.swift`

Secondary screens to audit after that:

- pushed variants with their own floating top chrome
- development screens that use `.safeAreaInset(edge: .top)`
- special immersive flows that currently rely on shell-level darkening

## Migration Steps

### Phase 1. Remove the wrong global ownership

- remove structural top shadow from:
  - `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/Navigation/MainAppView.swift`
- keep `MainAppView` responsible only for:
  - app background
  - tab bar
  - floating global menus

Exit:

- root shell no longer owns screen-specific top fade

### Phase 2. Introduce shared screen-level primitive

- add a reusable modifier/container in:
  - `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/DesignSystem/Components/`
  - or `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/DesignSystem/Modifiers/`
- internally reuse:
  - `/Users/ionsocol/Documents/SWIFT/QuizFlash/QuizFlash/Core/DesignSystem/Components/EdgeShadowOverlay.swift`

Rules:

- top-only
- no bottom edge support
- no per-screen custom z-index hacks

Exit:

- one shared primitive exists for all screen roots

### Phase 3. Migrate root layouts

For each root screen:

1. keep `background`
2. wrap content with top shadow
3. keep `.safeAreaInset(edge: .top)` chrome outside the shadow layer

Exit:

- top chrome remains readable above the fade
- content still transitions correctly underneath

### Phase 4. Remove duplicated local logic

After migration:

- remove screen-local edge shadow code that duplicates the shared primitive
- keep only screen-specific dim/fill behavior when it is truly separate from the generic top shadow

Example:

- `Library` may keep transient search-freeze dim if needed
- but should not keep a second structural top vignette

### Phase 5. QA

Verify on:

- Home
- Library
- Deck
- Create / Deck workspace
- Settings

Specifically test:

- expanded header state
- compact / collapsed header state
- search mode
- sticky title transitions
- pushed screens with back buttons
- bottom chrome hidden / visible

## Non-Goals

This refactor should not:

- reintroduce bottom edge shadow
- add local `zIndex` band-aids on random child views
- require every small reusable component to know about the edge shadow
- change the visual design of top chrome itself

## Risks

### 1. Some screens may rely on the shell shadow accidentally

Risk:

- after removing shell ownership, certain screens may lose the fade entirely until migrated

Mitigation:

- migrate root layouts in one focused pass

### 2. Duplicate shadow + local dim interactions

Risk:

- screens like `Library` may end up with both the shared shadow and a local dim effect

Mitigation:

- keep structural shadow and transient dim as separate responsibilities
- audit each migrated root after adoption

### 3. Safe-area math drift

Risk:

- some screens may compute different top heights and produce inconsistent fade depth

Mitigation:

- define shared height rules where possible
- keep only minimal per-screen adjustments tied to measured chrome height

## Proposed Deliverables

1. Shared top-edge-shadow screen primitive
2. Removal of shell-owned structural top shadow
3. Migration of main root layouts
4. Cleanup of duplicate local structural shadows
5. Manual QA pass across all top-chrome screens

## Success Criteria

- top shadow no longer darkens floating top chrome
- all major screens share the same top-edge treatment style
- bottom edge shadow is absent everywhere
- layering is controlled by architecture, not by ad-hoc `zIndex` fixes
- future screens can adopt the behavior by using one shared root-level primitive
