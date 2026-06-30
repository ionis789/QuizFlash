## Skills
A skill is a set of local instructions stored in a `SKILL.md` file.

### Available skills
- `quizflash-ios-engineer`: QuizFlash-specific coding guide for writing, reviewing, debugging, or refactoring Swift/SwiftUI/SwiftData code in this repository, especially architecture, navigation, concurrency, memory, and performance-sensitive changes. (file: `/Users/ionsocol/Documents/SWIFT/QuizFlash/.codex/skills/quizflash-ios-engineer/SKILL.md`)

### How to use skills
- Use `quizflash-ios-engineer` for any non-trivial QuizFlash app code change or code review.
- Open the skill's `SKILL.md` first, then start with the target file and the smallest paired owner file instead of preloading broad repo docs.
- If the smallest safe path is not obvious, read the skill's `references/task-routing.md` first.
- Read `references/project-map.md` only when ownership or placement is unclear.
- Read only the relevant parts of `references/architecture.md` when the task touches SwiftData, concurrency, navigation, `fullScreenSheet`, long-scroll surfaces, or performance-sensitive code.
- Check `references/component-catalog.md` only before creating a new reusable UI component.
- Prefer the skill's architectural rules over generic SwiftUI defaults when they conflict.
- If surrounding code still uses an older pattern, keep the change narrow unless the task explicitly asks for migration work.

## Workspace Verification Defaults
- For local simulator verification in this workspace, default to `iPhone 15 Pro (iOS 17.5)` unless the user explicitly asks for a different target.
- When reporting verification, prefer targeted `xcodebuild` runs against that simulator instead of broad generic destinations.
- For app run verification after a code change, prefer physical-device `build + install + launch` when the wired device `iPhoneIS` is connected:
  - Device: `iPhone 13 Pro`
  - Xcode destination id: `00008110-00041841340A401E`
  - CoreDevice identifier: `C0558BFB-25CA-5399-A247-927C3D727AA7`
- If that device is not connected, fall back to `build + run` on the default simulator instead of asking the user to press Run in Xcode.
