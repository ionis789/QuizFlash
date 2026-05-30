# Performance Profiling Protocol

Use this reference when QuizFlash has lag, scroll stutter, animation jank, memory growth, or suspected leaks that are not obvious from code inspection.

## When To Profile

- Profile after one narrow optimization if lag remains visible.
- Profile immediately when the user reports global scroll lag, memory growth, or "leak" behavior across data-heavy screens.
- Treat "leak" reports as either retain-cycle leaks or allocation churn until Instruments proves which one it is.

## Capture Instructions For The User

Ask for an Instruments `.trace` file, not a screen recording, when the cause is performance or memory.

Preferred setup:
- Target: `QuizFlash` running on `iPhone 15 Pro (iOS 17.5)` simulator unless the physical `iPhoneIS` device is connected and the issue is device-specific.
- Instruments template: include `Time Profiler` and `Allocations` in the same recording when possible.
- Optional instruments: `Hangs`, `Points of Interest`, and `Thermal State`.
- Recording mode: `Immediate`.
- Sampling: leave high-frequency/kernel/waiting-thread options off unless a first profile is inconclusive; they add overhead.
- Duration: 20-60 seconds.
- Gesture: start with 3-5 seconds idle, reproduce the lag with the exact scroll/drag/slider gesture, then stop.
- Send the saved `.trace` bundle as-is. A zip is optional only when upload tooling requires it.

If Instruments seems stuck building/running while Xcode normal build works, attach Instruments to the already-running `QuizFlash` process instead of launching from Instruments.

## Export Commands

First inspect the table of contents because traces can contain multiple runs:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun xctrace export \
  --input /path/to/profile.trace \
  --toc \
  --output /tmp/quizflash_trace_toc.xml
```

Export Time Profiler for the relevant run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun xctrace export \
  --input /path/to/profile.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  --output /tmp/quizflash_time_profile.xml
```

Export Allocations statistics for the relevant run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcrun xctrace export \
  --input /path/to/profile.trace \
  --xpath '/trace-toc/run[@number="1"]/tracks/track[@name="Allocations"]/details/detail[@name="Statistics"]' \
  --output /tmp/quizflash_alloc_stats.xml
```

If `run="1"` is the wrong run, use the run number from the TOC. A single `.trace` may contain both Time Profiler and Allocations runs.

## How To Interpret

Prioritize evidence in this order:

1. Time Profiler app-inclusive stacks. Ignore leaf noise from dyld, PAC, backtrace, or Instruments overhead unless it remains after filtering to app symbols.
2. Main-thread samples during the gesture.
3. SwiftUI body getters, row body getters, computed properties, `.task(id:)` signatures, and GeometryReader/update paths.
4. SwiftData/CoreData model-property reads, relationship traversal, and repeated `@Query` collection walks.
5. Allocations total/transient bytes and event counts. Heavy transient allocations often mean churn, not a retain-cycle leak.
6. Hangs table. If no >250ms hangs appear but the UI feels bad, treat it as frame-time churn rather than one blocking call.

Known QuizFlash pattern from the Home incident:
- `HomeView.body` repeatedly built `.task(id:)` signatures by fingerprinting `@Query` arrays.
- The fingerprint loops touched many SwiftData model properties, causing CPU and allocation churn.
- Calendar cells called `Calendar`/ICU-backed work during render.
- Fix: cache signatures/snapshots outside `body`, invalidate from cheap signals, and precompute repeated calendar values in the view model.

## Fix Strategy

Use the profile to remove work from the hot path, not just to micro-optimize the visible symptom:

- Move heavy derived values out of `body` and row computed properties.
- Replace full model walks with cached revisions or immutable snapshots.
- Keep `.task(id:)` keys cheap; compute heavy fingerprints inside the task or view model only when a cheap signal changes.
- Convert repeated row inputs to display-ready snapshot structs.
- Use denormalized counters instead of relationship `.count`.
- Move heavy card/zone/blob reads to actors such as `CardFetchActor`.
- Precompute calendar/date/formatter values used by repeated cells.
- Keep scroll offsets, drag progress, and frame-by-frame geometry out of observed state unless the state is deliberately local and cheap.

## Verification

After patching:

1. Run the targeted build for `iPhone 15 Pro (iOS 17.5)`.
2. Ask the user to repeat the same gesture.
3. If lag remains, capture a second trace and compare top app-inclusive stacks against the first trace. The old hotspot should disappear or fall below the next bottleneck.
