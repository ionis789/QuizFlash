## Skills
A skill is a set of local instructions stored in a `SKILL.md` file.

### Available skills
- `quizflash-ios-engineer`: QuizFlash-specific coding guide for writing, reviewing, debugging, or refactoring Swift/SwiftUI/SwiftData code in this repository, especially architecture, navigation, concurrency, memory, and performance-sensitive changes. (file: `/Users/ionsocol/Documents/SWIFT/QuizFlash/.codex/skills/quizflash-ios-engineer/SKILL.md`)

### How to use skills
- Use `quizflash-ios-engineer` for any non-trivial QuizFlash app code change or code review.
- Open the skill's `SKILL.md` first, then load only the reference files needed for the task.
- Prefer the skill's architectural rules over generic SwiftUI defaults when they conflict.
- If surrounding code still uses an older pattern, keep the change narrow unless the task explicitly asks for migration work.
