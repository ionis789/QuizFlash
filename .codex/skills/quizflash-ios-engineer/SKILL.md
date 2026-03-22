---
name: quizflash-ios-engineer
description: Project-specific engineering guide for QuizFlash, a SwiftUI flashcard app targeting iOS 17+ with Swift 6, SwiftData, and `@Observable`. Use when Codex writes, reviews, debugs, or refactors code in this repository, especially for SwiftUI views, view models, SwiftData models, background fetch actors, navigation, theming, memory/performance work, and QuizFlash file-format or output conventions.
---

# QuizFlash iOS Engineer

## Overview

Write and review code for QuizFlash using the repository's architecture rules instead of generic SwiftUI defaults. Treat the standards in `references/architecture.md` as the target for new code even when older files still contain legacy patterns.

## Quick Start

1. Read `references/project-map.md` to locate the feature or layer you are touching.
2. Read `references/architecture.md` before any non-trivial implementation, refactor, or review.
3. Verify `references/component-catalog.md` before creating any new UI component.
4. Reuse existing project primitives before introducing new abstractions:
   - `NavigationManager`
   - `UIConstants`
   - `ThemeManager`
   - `ModelContext.safeModel(for:as:)`
   - `CardFetchActor`
   - `ImageCache`
   - `MathWebViewPool`
   - `ScrollPositionRestorer`
   - `fullScreenSheet` from `Core/DesignSystem/Modifiers/View+FullScreenSheet.swift`
   - `StandardSheetTopStripBackground` for immersive dark sheets that react to drag-dismiss progress

## Workflow

1. Identify the ownership layer first.
   - Keep `Domain/Models/` data-oriented.
   - Keep `Features/*/ViewModels/` focused on business logic and async orchestration.
   - Keep `Views/` and `Components/` focused on rendering and event forwarding.
2. Follow the repository's data-access rules before changing SwiftData code.
   - Prefer denormalized counters over relationship `.count`.
   - Route heavy card-content reads through `CardFetchActor`.
   - Save mutations explicitly and surface failures.
3. Match the project's UI system before changing presentation code.
   - Use `UIConstants` tokens instead of magic numbers.
   - Prefer semantic colors and existing theme plumbing.
   - Keep navigation programmatic through `NavigationManager`.
   - Treat long scrolling surfaces and immersive modal flows as architecture-sensitive code paths, not local view tweaks.
   - On drag-heavy or scroll-heavy surfaces, do not leave expensive collection-wide work in view `computed` properties.
   - If a value walks many cards, zones, diagnostics, or summaries, cache it in local state or move it out of the hot render path, then recompute only when the source collection actually changes.
   - Prefer `Equatable` row views and other diff-friendly techniques for large editor/deck lists so parent refreshes do not rebuild every row.
4. Preserve the repo's file hygiene when generating or rewriting files.
   - Keep Apple-style file headers.
   - Keep `// MARK: -` sections.
   - Keep DocC comments on new internal and public declarations.
   - Remove `TODO:`, `FIXME:`, and commented-out code from generated output.

## Testing Expectations

1. Treat data-flow regressions as testable by default.
   - When a change creates, edits, deletes, imports, exports, converts, or otherwise mutates persisted app data, add or update automated tests unless the user explicitly says not to.
2. Prefer logic and persistence tests over UI automation.
   - Use `XCTest` suites in `QuizFlashTests/` to validate models, view models, stores, import/export, and detached persistence flows.
   - Leave UI validation to manual verification unless the task explicitly asks for UI tests.
3. Use deterministic in-memory fixtures for SwiftData.
   - Prefer a dedicated in-memory `ModelContainer` test helper over production storage.
   - Seed relationships in the direction the production code actually reads (`deck.cards`, `deck.folder`, etc.) to avoid SwiftData registration traps.
4. Verify tests conservatively on one simulator at a time.
   - Prefer `build-for-testing` once, then `test-without-building` per suite or class.
   - Disable parallel testing for local verification unless the user explicitly wants parallel runs.
   - Unless the user explicitly asks for a different target, default to the currently active simulator set for this repo: `iPhone 15 Pro (iOS 17.5)`.
   - When reporting verification, prefer targeted `xcodebuild` test runs against that active simulator instead of broader generic destinations.
5. Extend the regression net when fixing a bug.
   - If a data-flow bug is discovered while testing, fix the fixture or production code at the root cause and keep the new test as a permanent guardrail.

## Decision Points

- Inspect `references/project-map.md` before adding a new type if you are not sure where it belongs.
- Read `references/architecture.md` end to end before touching navigation, concurrency, SwiftData, or performance-sensitive code.
- Read `references/architecture.md` before changing any large `ScrollView`, sticky hero, floating top chrome, or custom full-screen presentation.
- Prefer the standards in this skill for new code. If a surrounding file still uses an older pattern, keep the change narrow unless the task explicitly asks for cleanup.
- Read `../../../quizflash_mcp_prompt.md` only when you need the original long-form source prompt that this skill was derived from.

## References

- `references/project-map.md`: Real repo layout, important files, and common starting points.
- `references/architecture.md`: Project rules for architecture, concurrency, SwiftData safety, navigation, design tokens, code style, and review checks.
- `references/examples/ViewModel.swift.example`: Canonical QuizFlash-flavored view-model skeleton for new code.
- `references/examples/View.swift.example`: Canonical QuizFlash-flavored root-view skeleton for new screens.
- `references/component-catalog.md`: Reusable UI inventory; check this before creating a new component.
- `references/antipatterns.md`: Concrete "before/after" guidance for patterns that still appear in older files.
- `references/new-feature-template.md`: End-to-end feature scaffold and implementation order.
- `references/universal_prompt.md`: Copy-paste prompt template for other agents/tools.

## Before Writing Any New Feature

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

When you use Claude/ChatGPT/Cursor/etc. outside Codex, paste or attach:
- `SKILL.md`
- `references/architecture.md`
- `references/project-map.md`

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
