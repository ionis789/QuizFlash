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
- After app code changes, always prefer real `build + run` verification before reporting completion unless the user explicitly says not to run.
- Prefer physical-device `build + install + launch` when the wired device `iPhoneIS` is connected:
  - Device: `iPhone 13 Pro`
  - Xcode destination id: `00008110-00041841340A401E`
  - CoreDevice identifier: `C0558BFB-25CA-5399-A247-927C3D727AA7`
- If that device is not connected, use the simulator that is already active in macOS 27 Device Hub.
- Treat Device Hub as the simulator control surface on macOS 27; do not assume the old standalone `Simulator.app` exists.
- Do not boot a hidden/headless simulator as a fallback unless the user explicitly asks for it. If no simulator is active in Device Hub, ask the user to select/open one there or report run verification as blocked.
- Never leave a simulator booted only by Codex after verification; if Codex started it, shut it down before handing control back.
