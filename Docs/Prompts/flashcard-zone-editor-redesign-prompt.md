# Flashcard Zone Editor Redesign Prompt

Use this prompt when implementing the next major redesign of the QuizFlash
flashcard editor. The goal is not a small visual tweak. The goal is to turn the
current flashcard editor into a reusable, zone-based rich text editor that can
power Flashcards and Quiz authoring surfaces.

## Role

You are a senior iOS engineer working in the QuizFlash SwiftUI codebase.

You must design and implement a production-quality zone editor for iOS 17.5+
using the existing QuizFlash architecture, design system, and play-mode card
layout rules. The result must feel native, minimal, direct, and consistent with
the rest of the app.

Do not patch around symptoms. Analyze the current editor, identify the real
layout and interaction ownership problems, and replace fragile local behavior
with a reusable editor system.

## Required Project Rules

- Use the `quizflash-ios-engineer` skill before editing code.
- Treat iOS 17.5 as the compatibility baseline.
- Prefer existing project primitives: `UIConstants`, semantic colors,
  `fullScreenSheet`, app top chrome rules, localization helpers, and existing
  flashcard layout components.
- Do not use native SwiftUI toolbar behavior if it can regress after custom
  preview sheets on iOS 17.5.
- Keep all new user-facing copy localization-ready for English, Romanian, and
  Russian.
- Do not add dead code, debug leftovers, stale comments, or unused layout
  branches.
- Do not visually verify on behalf of the user unless explicitly requested.
  Build and targeted simulator verification are enough unless the user asks for
  screenshots.

## Current Problems To Fix

The current editor has several structural problems:

- The editor card does not behave like the real flashcard surface.
- The selected zone can become a forced fixed-size block even when its content
  should use auto size.
- The editor confuses three separate concepts:
  - zone size
  - zone block alignment inside the card
  - text alignment inside the zone
- The current "auto alignment" is actually smart centered block layout, not
  normal text alignment.
- Changing a zone alignment in the editor does not reliably affect the real
  flashcard rendering.
- The editor preview and the play-mode flashcard are not synchronized enough.
- The `Question` / `Answer` switch is visually too large and wastes vertical
  space.
- Top buttons are not positioned in a clean app-standard way.
- Creating zones by tapping empty card space no longer works reliably.
- The UI does not communicate that this is a zone-based editor.
- The editor is too flashcard-specific even though the same editing model will
  be needed by other play modes.
- Opening preview and closing it previously caused the editor top controls to
  disappear or become unreachable. This must never regress.

## Product Goal

Build a reusable zone editor that lets the user compose card content as natural
semantic blocks:

- one or more text/math zones
- future image/sketch/media zones
- zones that can be selected, edited, moved, aligned, resized, and styled
- a card canvas that behaves like the actual rendered flashcard surface
- clear editing affordances without noisy explanatory text

The editor must be simple at first glance and powerful when editing:

- top chrome: minimal, app-standard, reliable
- side switch: compact, not dominant
- card canvas: real flashcard proportions
- zones: obvious when selected, subtle when idle
- formatting bar: contextual and ergonomic
- preview: uses the same rendered card semantics as play mode

## Core Architecture Requirement

Separate these layout concepts explicitly in data and rendering code:

### 1. Zone Size Mode

This controls the rectangle occupied by the zone.

Required modes:

- `auto`: zone wraps to its measured content size, with internal padding and
  max constraints from the card.
- `fillWidth`: zone uses the available card content width but keeps intrinsic
  height.
- `fixed`: zone uses an explicit user-sized rectangle.

Important:

- `auto` must not force the zone to the full available width.
- `auto` must not collapse mathematical WebKit content.
- `auto` must preserve enough width for natural wrapping when the content fits.
- `fixed` must be used only when the user deliberately resizes a zone.

### 2. Zone Block Alignment In Card

This controls where the zone rectangle sits inside its parent layout.

Required block alignment options:

- leading
- center
- trailing
- auto

`auto` means "smart centered block layout":

- Estimate/render the zone's natural block width.
- Center the block as a whole inside the available card area.
- Keep the text lines internally leading by default unless text alignment says
  otherwise.
- This is the behavior previously described as "Deck Grid Guides" and
  "FlashCard Grid Guides".

Important:

- Auto block alignment must not be mixed with plain text alignment.
- Each semantic zone is an independent block.
- A zone's auto alignment must not use another zone's width to decide its own
  block width.
- Multi-zone cards must preserve vertical zone relationships.

### 3. Text Alignment Inside Zone

This controls only the text lines inside the zone rectangle.

Required text alignment options:

- leading
- center
- trailing

Important:

- Text alignment must be visible in the editor and in play/preview.
- Text alignment must not change the zone size mode.
- Text alignment must not override block alignment.
- Text alignment must work for plain text and mixed markdown/math content.

## Naming Requirement

Do not call smart block alignment simply "center" in UI or data if that creates
confusion.

Suggested model naming:

- `ZoneSizeMode`
- `ZoneBlockAlignment`
- `ZoneTextAlignment`
- `ZoneLayoutPreset`

Suggested UI naming:

- "Auto Block" or an icon-only control for smart auto block alignment.
- Standard text alignment icons for line alignment.
- Avoid long labels in the editor surface.

## Rendering Requirement

The editor, preview, deck thumbnails, and flashcard play mode must share the
same layout engine or the same deterministic layout rules.

You must not maintain separate ad hoc layout math in:

- deck grid cards
- flashcard play mode
- flashcard editor
- preview mode

Create or extract a reusable layout layer if needed.

Suggested reusable responsibilities:

- measure zone content
- choose zone block width
- choose zone block height
- position zones vertically
- apply block alignment
- apply text alignment
- expose debug metrics in development builds

Suggested target names:

- `CardZoneLayoutEngine`
- `CardZoneLayoutSpec`
- `CardZoneLayoutResult`
- `CardZoneRenderMetrics`
- `ZoneEditorCanvas`
- `ZoneEditorCardSurface`

Use the existing `FlashcardGridContentLayout` / estimator work where it is
correct, but do not keep fragile assumptions if they only work in play mode.

## Measurement Requirement

Measurement must handle both native SwiftUI text and WebKit/math content.

Known difficult content:

- plain text with spaces
- markdown bold and italic
- inline math mixed with text
- display-style math
- wide formulas
- matrices and bracketed expressions
- formulas requiring horizontal scroll
- Romanian diacritics
- symbols with ascenders/descenders that change visual bounds

Rules:

- Plain text must preserve spaces. Words must never visually glue together.
- WebKit/math zones must remain tappable for card flip in play mode when they
  are not being edited.
- WebKit/math zones that overflow horizontally must keep horizontal scroll where
  appropriate.
- Rendered height must not be guessed as one line when WebKit content is taller.
- Measurement fallback must be conservative: if exact height is unknown, reserve
  enough height, not too little.
- Editor measurement and play-mode measurement must converge as closely as
  practical.

## Editor Interaction Requirements

The editor must behave like an advanced zone-based text editor.

Required interactions:

- Tap empty card space to create a new zone at the tapped location or nearest
  valid insertion point.
- Tap a zone to select it.
- Tap selected text zone to edit text.
- Drag selected zone to reposition it when move mode is active.
- Add zone above/below selected zone.
- Duplicate selected zone.
- Delete selected zone.
- Move selected zone up/down in vertical order.
- Change zone size mode.
- Change block alignment.
- Change text alignment.
- Change font size preset.
- Toggle bold/italic for selected text where supported.
- Insert image/sketch/media when supported by the current card type.

Do not let editing gestures fight with scroll gestures or sheet dismissal.
On iOS 17.5, test gesture ownership carefully.

## Empty Space Zone Creation

Tap-to-create zones is mandatory.

Expected behavior:

- If the card has no zones, tapping inside the card creates the first text zone
  near the tap and focuses it.
- If the card has zones, tapping empty space between zones creates a new zone at
  the nearest semantic insertion point.
- Tapping empty space below all zones appends a new zone.
- Tapping outside the card does not create a zone.
- Tapping a control overlay does not create a zone.

The editor must make this feel intentional, not accidental.

## UI Redesign Requirements

The editor screen must be redesigned, not superficially adjusted.

### Background

- Use the app's main black background.
- Avoid decorative gradients, blur blobs, or unnecessary visual effects.

### Top Chrome

Use a custom top menu consistent with the rest of QuizFlash:

- app-standard top safe-area rhythm
- large rounded controls when needed
- icons instead of verbose text where clear
- save/check primary action
- close/cancel action
- media/sketch/preview actions
- no native toolbar dependency

The top controls must remain visible and usable after:

- opening preview
- dismissing preview
- focusing keyboard
- dismissing keyboard
- switching Question/Answer
- rotating/resizing iPad window

### Question / Answer Switch

The side switch must be compact and secondary.

Requirements:

- Do not make it a huge dominant pill.
- It should be easy to tap, but not consume a large vertical band.
- It should visually fit between top chrome and card canvas.
- It should clearly show current side.
- It should not push the card too low.

Possible designs:

- compact segmented capsule
- two small pill buttons
- centered side selector with current side emphasized

### Card Canvas

The editor card must use real flashcard proportions.

Requirements:

- Same rounded-card feel as flashcard play mode.
- Same content padding semantics as play mode where possible.
- Selected zone outlines should sit inside the card content area.
- Idle zones should be visible enough for editing but not noisy.
- The canvas should invite adding zones by tapping empty space.

### Formatting Bar

The bottom formatting bar should be contextual and reusable.

Requirements:

- Do not overload one bar with unrelated controls.
- Use icon buttons for alignment, size, style, move, duplicate, delete.
- Use compact menus/sheets for secondary options.
- Keep "Done" or keyboard dismissal clear when editing text.
- Preserve safe-area and keyboard behavior on iOS 17.5.

## Alignment UX Requirement

The UI must expose the difference between block alignment and text alignment.

Do not show only one generic "alignment" menu.

Recommended controls:

- Block position control: auto/left/center/right zone block.
- Text lines control: left/center/right text lines.

If the UI needs to stay minimal, use icons and short labels in a secondary
popover/sheet. The behavior must still be understandable.

## Data Migration Requirement

Existing cards must continue to render correctly.

If current stored data has one old alignment field, migrate it carefully:

- old `.leading` should likely map to:
  - `blockAlignment: .auto` or `.leading` depending on current app behavior
  - `textAlignment: .leading`
  - `sizeMode: .auto`
- old `.center` should map explicitly, not accidentally.
- old `.trailing` should map explicitly.

Decide and document the migration mapping before writing code.

Do not break existing decks.
Do not silently reinterpret user-authored cards in a surprising way.

## Reusable Editor Scope

The new editor must be designed for reuse.

Flashcards are the first implementation, but the editor layer should be usable
by:

- Quiz question/explanation zones
- future rich study card surfaces

Do not bake flashcard-only assumptions into the reusable canvas.

Flashcard-specific code may own:

- front/back side switching
- flashcard preview
- save into `CardModel`
- flashcard-specific media affordances

Reusable code should own:

- zone canvas
- zone selection
- zone editing
- zone layout
- zone formatting controls
- measurement/debug instrumentation

## Suggested File Targets

Start by inspecting:

- `QuizFlash/Features/DeckEditor/Views/FlashcardEditorView.swift`
- `QuizFlash/Features/DeckEditor/Views/ZoneView.swift`
- `QuizFlash/Features/DeckEditor/Views/CardPreviewModeView.swift`
- `QuizFlash/Features/PlayMode/FlashCardsMode/Components/FlipCard.swift`
- `QuizFlash/Features/PlayMode/FlashCardsMode/Components/FlashcardGridContentLayout.swift`
- `QuizFlash/Features/DeckEditor/ViewModels/FlashcardEditorViewModel.swift`

If creating reusable editor components, prefer a clear folder such as:

- `QuizFlash/Features/DeckEditor/Components/ZoneEditor/`

or another existing feature-local component location if the project map shows a
better owner.

Do not scatter the implementation across unrelated feature folders.

## Debug Requirement

Because this editor has already had repeated layout regressions, add useful
development diagnostics instead of guessing.

Debug must help answer:

- What is the selected zone id?
- What is its size mode?
- What is its block alignment?
- What is its text alignment?
- What is the measured content size?
- What is the rendered content size?
- What is the card content rect?
- What is the zone rect?
- Which layer received a tap?
- Did a tap create a zone, select a zone, edit a zone, or do nothing?

Rules:

- Gate debug UI behind existing debug/development controls.
- Keep diagnostics easy to copy.
- Do not show debug UI in normal user mode.
- Remove temporary probes unless they become a useful permanent dev tool.

## iOS 17.5 Interaction Risks

Be conservative with:

- `UIViewRepresentable` and `UIViewControllerRepresentable`
- WebKit views inside clipped/masked SwiftUI containers
- `.compositingGroup()`
- SwiftUI `.clipShape()` around interactive hosted views
- overlays that intercept taps
- gestures attached to parent containers
- custom sheets and keyboard state

Known rule:

- Visual correctness on iOS 18 or newer does not prove interaction correctness
  on iOS 17.5.

If a WebKit/math zone is not in edit mode, tapping it in play mode must still
allow the card-level flip behavior unless horizontal scroll is actively used.

## Build And Verification

At minimum, run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project QuizFlash.xcodeproj \
  -scheme QuizFlash \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.5' \
  build
```

Also verify through targeted manual or simulator interaction if requested:

- open flashcard editor
- switch Question/Answer
- tap empty card space to create a zone
- type text
- change size mode
- change block alignment
- change text alignment
- open preview
- close preview
- confirm top controls still work
- save
- reopen card
- compare editor/preview/play-mode layout

## Acceptance Criteria

The implementation is acceptable only if:

- Editor top controls never disappear after preview dismissal.
- `Question` / `Answer` switch is compact and visually secondary.
- Tapping empty card space creates zones again.
- Auto alignment does not force all zones to full width.
- A selected auto-size zone hugs content naturally.
- Fill-width and fixed-size zones still exist when intentionally chosen.
- Text alignment changes text lines inside the selected zone.
- Block alignment changes the selected zone's position inside the card.
- Smart auto block alignment remains available and clear.
- Editor card proportions match flashcard play mode.
- Editor and preview are visually consistent enough that preview is not a
  surprise.
- Existing cards are migrated or interpreted safely.
- Plain text spaces are preserved.
- WebKit/math content remains usable and tappable.
- No dead code, stale debug, or unrelated refactor churn remains.

## Implementation Strategy

Recommended sequence:

1. Audit current data model and determine how zone alignment is stored.
2. Define the new layout concepts and migration mapping.
3. Extract a reusable layout engine or shared layout spec.
4. Build the reusable zone editor canvas.
5. Port `FlashcardEditorView` to the new canvas.
6. Rebuild the top chrome and compact side switch.
7. Restore tap-to-create zones.
8. Wire block alignment and text alignment as separate controls.
9. Ensure preview uses the same rendering semantics as play mode.
10. Add debug metrics for editor layout and tap routing.
11. Run build verification on iOS 17.5.
12. Remove any temporary instrumentation not behind debug controls.

## Non-Goals

Do not:

- add a new AI generation algorithm
- redesign unrelated deck screens
- change study-session scoring
- change SwiftData card relationships unless migration requires it
- add decorative onboarding text
- hide the core problems behind fixed padding values
- solve editor/play-mode mismatch with separate one-off math in each screen

## Final Report Template

When finished, report briefly:

- files changed
- architecture decision for zone size/block/text alignment
- migration behavior for old cards
- iOS 17.5 build result
- any known limitations
