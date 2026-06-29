## Skills
A skill is a set of local instructions stored in a `SKILL.md` file.

### Available skills
- `quizflash-ios-engineer`: QuizFlash-specific coding guide for writing, reviewing, debugging, or refactoring Swift/SwiftUI/SwiftData code in this repository, especially architecture, navigation, concurrency, memory, and performance-sensitive changes. (file: `/Users/ionsocol/Documents/SWIFT/QuizFlash/.codex/skills/quizflash-ios-engineer/SKILL.md`)
- `graphify`: Queryable knowledge graph for codebase architecture, ownership, file relationships, and cross-file project context. Use it before broad raw file exploration when `graphify-out/graph.json` exists. (file: `/Users/ionsocol/Documents/SWIFT/QuizFlash/.codex/skills/graphify/SKILL.md`)

### How to use skills
- Use `quizflash-ios-engineer` for any non-trivial QuizFlash app code change or code review.
- Use `graphify` for architecture, ownership, dependency, file-relationship, and broad codebase-navigation questions, especially before reading many raw files.
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

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `$graphify` or asks to use Graphify, load the `graphify` skill before doing anything else.

Rules:
- If `graphify` is not on `PATH`, use `/Users/ionsocol/Library/Python/3.14/bin/graphify`.
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
