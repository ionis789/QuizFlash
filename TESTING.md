# QuizFlash Data-Flow Tests

These tests verify data mutations and persistence behavior, not UI rendering.

## Test Categories

- `ai`
  Covers provider-profile persistence and paused AI generation session persistence.
- `authoring`
  Covers create, edit, delete, and draft reconciliation in deck authoring.
- `decks`
  Covers deck-detail mutations like add, pin, delete, bulk delete, and grouping persistence.
- `home`
  Covers folder and exam-goal mutations from Home flows.
- `library`
  Covers library delete, move, and import mutations.
- `play`
  Covers play-mode settings persistence and review-session persistence.
- `storage`
  Covers `.qflash` import/export, storage accounting, and cleanup flows.

## What These Tests Check

- deck creation, editing, deletion, and draft reconciliation
- card add, delete, pin, bulk delete, and deck grouping persistence
- folder and exam-goal mutations
- play-mode settings persistence
- review history, daily log, and XP persistence
- `.qflash` export/import round-trips
- storage accounting and deck cleanup
- AI provider profile persistence and paused AI session persistence

## How The Tests Work

The tests create an in-memory SwiftData container and call view models, stores, and services directly.
After each mutation, they assert on the persisted models and counters.

This means:

- they do check whether the app's data flow still behaves correctly
- they do not tap buttons or verify screen layout
- they are meant to catch regressions after code changes

## Why A Simulator Is Still Required

The current `QuizFlashTests` target is a hosted iOS unit-test target.
So these are not UI tests, but they still run inside the iOS test runtime and need one simulator destination.

If you want truly simulator-free logic tests later, we would need to move more code into a separate non-hosted module or package.

## Safe Manual Runner

Use the root script:

```sh
./run_data_tests.sh
```

Important behavior:

- runs serially
- uses one simulator only
- does not auto-boot any simulator unless you pass `--boot-default`

## Common Commands

List suites:

```sh
./run_data_tests.sh --list
```

List categories:

```sh
./run_data_tests.sh --list-categories
```

Run all suites on the currently booted simulator:

```sh
./run_data_tests.sh
```

Run one category:

```sh
./run_data_tests.sh --category play
```
    
Run multiple categories:

```sh
./run_data_tests.sh --category ai --category storage
```

Run one suite:

```sh
./run_data_tests.sh --suite HomeViewModelTests
```

Run multiple suites:

```sh
./run_data_tests.sh --suite HomeViewModelTests --suite DeckViewModelMutationTests
```

Run on a specific simulator:

```sh
./run_data_tests.sh --simulator-id YOUR_DEVICE_ID
```

Boot one simulator automatically, then run:

```sh
./run_data_tests.sh --boot-default
```

Skip the build step if you already ran `build-for-testing` and only want to rerun suites:

```sh
./run_data_tests.sh --skip-build --suite HomeViewModelTests
```

## Running From Xcode

You can also run the `QuizFlash` scheme with `Cmd-U`.

The script is safer for routine regression checks because it keeps the workflow explicit:

- one simulator
- no parallel test execution
- optional category-by-category or suite-by-suite runs
