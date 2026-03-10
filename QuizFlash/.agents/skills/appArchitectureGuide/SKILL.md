---
trigger: always_on
---

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
3. Reuse existing project primitives before introducing new abstractions:
   - `NavigationManager`
   - `UIConstants`
   - `ThemeManager`
   - `ModelContext.safeModel(for:as:)`
   - `CardFetchActor`
   - `ImageCache`
   - `MathWebViewPool`
   - `ScrollPositionRestorer`
   - `fullScreenSheet` from `Core/DesignSystem/Modifiers/View+FullScreenSheet.swift`

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
4. Preserve the repo's file hygiene when generating or rewriting files.
   - Keep Apple-style file headers.
   - Keep `// MARK: -` sections.
   - Keep DocC comments on new internal and public declarations.
   - Remove `TODO:`, `FIXME:`, and commented-out code from generated output.

## Decision Points

- Inspect `references/project-map.md` before adding a new type if you are not sure where it belongs.
- Read `references/architecture.md` end to end before touching navigation, concurrency, SwiftData, or performance-sensitive code.
- Read `references/architecture.md` before changing any large `ScrollView`, sticky hero, floating top chrome, or custom full-screen presentation.
- Prefer the standards in this skill for new code. If a surrounding file still uses an older pattern, keep the change narrow unless the task explicitly asks for cleanup.
- Read `../../../quizflash_mcp_prompt.md` only when you need the original long-form source prompt that this skill was derived from.

## References

- `references/project-map.md`: Real repo layout, important files, and common starting points.
- `references/architecture.md`: Project rules for architecture, concurrency, SwiftData safety, navigation, design tokens, code style, and review checks.
