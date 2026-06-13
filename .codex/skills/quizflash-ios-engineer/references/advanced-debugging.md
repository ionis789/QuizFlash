# Advanced Debugging Protocol

Use this protocol when:

- the user explicitly requests `debug avansat`, detailed debug, or a complete flow;
- one behavioral fix has already failed;
- more than one ownership layer can explain the symptom;
- the bug is intermittent, timing-sensitive, or depends on SwiftUI/UIKit/WebKit/async boundaries.

Do not apply another behavioral fix until the trace proves one owning layer.

## 1. Define The Decision Tree

Before editing, list the plausible layers and the signal that distinguishes each one.

Example for a rendered zone:

- no renderer execution: lifecycle/readiness failure;
- renderer executes but emits no metrics: renderer/bridge failure;
- metrics arrive but are rejected: validation/state bridge failure;
- metrics are accepted then cleared: invalidation/reset failure;
- valid metrics survive but final frame differs: layout engine/application failure.

Tell the user what output will select each branch.

## 2. Instrument The Complete Flow

Record a bounded chronological event flow, not only final values:

1. input identity and normalized payload;
2. instance creation/reuse and owner ID;
3. state before the operation;
4. lifecycle/readiness events;
5. operation execution and token/generation;
6. raw callback or measurement;
7. validation and clamp decisions;
8. accepted state mutation;
9. every reset/invalidation and its exact cause;
10. fallback selection;
11. final value/frame applied by the consumer.

Every event should answer:

- `what changed?`
- `who changed it?`
- `from what value to what value?`
- `why was it accepted, rejected, reset, or ignored?`
- `which identity/token/zone/view did it belong to?`

## 3. Preserve Early Events

Do not start collecting only when a debug overlay is opened. Initialization and first-layout failures happen earlier.

- Keep a small ring buffer active from creation time.
- Bound it to roughly 12-30 high-signal events per instance.
- Keep expensive geometry/token dumps conditional on debug visibility.
- Keep lightweight lifecycle, measurement, reset, and decision events continuously in DEBUG builds.

## 4. Make Output Exportable

Prefer one copyable text export containing:

- reproduction timestamp and stable object IDs;
- current inputs/settings;
- final snapshot;
- chronological event flow;
- counters for executions, callbacks, resets, retries, and errors;
- raw and applied values;
- rejection/reset reasons.

Use stable labels so two exports can be diffed. Avoid relying only on console logs, which may be unavailable to the tester.

## 5. Compare Failing And Working Paths

Instrument a failing object and a working sibling through the same pipeline. Compare the first event where they diverge.

Do not assume a visibly wrong component never produced a valid result. A common failure pattern is:

```text
valid measurement -> accepted state -> unrelated identity change -> state reset
-> producer does not emit again because its value is unchanged -> stale fallback wins
```

Therefore always record both production and later invalidation of a value.

## 6. Collaborate With The Tester

The user is the runtime tester.

1. Build, install, and launch the instrumented app.
2. Give exact reproduction steps and name the output section needed.
3. Ask for the exported text plus a screenshot/video only when visual timing matters.
4. Read the trace before editing behavior.
5. Explain the proven divergence in concrete values.
6. Apply one narrowly scoped fix at the owning layer.
7. Keep diagnostics until the user confirms the behavior.

Do not repeatedly ask for generic videos when an exportable state flow can answer the question.

## 7. Patch From Evidence

The fix must correspond directly to the first proven divergence.

- Lifecycle failure: fix readiness/ownership.
- Missing callback: fix producer or bridge.
- Rejected valid value: fix validation.
- Accepted value later cleared: fix invalidation policy.
- Correct state but wrong frame: fix final layout application.

Preserve unrelated gesture, focus, animation, and rendering paths.

## 8. Validate And Clean Up

- Build against the workspace target.
- Reproduce the original failing case and at least one working/short case.
- Confirm the event flow now reaches the expected final state.
- Retain generally useful DEBUG diagnostics.
- Remove temporary noisy probes that add runtime cost or obscure normal debug output.

In the final report, state:

- the first divergent event;
- the owning layer;
- the exact fix;
- the verification performed;
- any diagnostics intentionally retained.
