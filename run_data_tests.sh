#!/bin/zsh

# Manual runner for QuizFlash data-flow regression tests.
# Runs hosted XCTest suites serially on a single iOS Simulator destination.

set -euo pipefail

readonly REPO_ROOT="/Users/ionsocol/Documents/SWIFT/QuizFlash"
readonly PROJECT_PATH="$REPO_ROOT/QuizFlash.xcodeproj"
readonly SCHEME="QuizFlash"
readonly DERIVED_DATA_PATH="${QUIZFLASH_DERIVED_DATA_PATH:-/tmp/QuizFlashDerivedDataTests}"
readonly XCODE_DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
readonly XCODE_PATH="$XCODE_DEVELOPER_DIR/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin"

typeset -a ALL_SUITES=(
  "AIProviderStoreTests"
  "AIJobSessionStoreTests"
  "AIGenerationSessionStoreTests"
  "AIWorkspaceCoordinatorTests"
  "MatchConversionPipelineTests"
  "CreateDeckViewModelTests"
  "MatchQualityAndReadinessTests"
  "HomeViewModelTests"
  "LibraryViewModelMutationTests"
  "DeckViewModelMutationTests"
  "DeckCardConversionRequestTests"
  "DeckConversionPersistenceTests"
  "DeckPlayModeSettingsStoreTests"
  "PlaySessionPersistenceServiceTests"
  "DeckSharingManagerTests"
  "StorageAndCleanupTests"
)

typeset -a CATEGORY_AI_SUITES=(
  "AIProviderStoreTests"
  "AIJobSessionStoreTests"
  "AIGenerationSessionStoreTests"
  "AIWorkspaceCoordinatorTests"
  "MatchConversionPipelineTests"
)

typeset -a CATEGORY_AUTHORING_SUITES=(
  "CreateDeckViewModelTests"
  "MatchQualityAndReadinessTests"
)

typeset -a CATEGORY_DECKS_SUITES=(
  "DeckViewModelMutationTests"
  "DeckCardConversionRequestTests"
  "DeckConversionPersistenceTests"
)

typeset -a CATEGORY_HOME_SUITES=(
  "HomeViewModelTests"
)

typeset -a CATEGORY_LIBRARY_SUITES=(
  "LibraryViewModelMutationTests"
)

typeset -a CATEGORY_PLAY_SUITES=(
  "DeckPlayModeSettingsStoreTests"
  "PlaySessionPersistenceServiceTests"
)

typeset -a CATEGORY_STORAGE_SUITES=(
  "DeckSharingManagerTests"
  "StorageAndCleanupTests"
)

typeset -a CATEGORY_ORDER=(
  "ai"
  "authoring"
  "decks"
  "home"
  "library"
  "play"
  "storage"
)

typeset -a REQUESTED_SUITES=()
typeset -a REQUESTED_CATEGORIES=()

SIMULATOR_ID=""
BOOT_DEFAULT_SIMULATOR=0
SKIP_BUILD=0
LIST_ONLY=0
LIST_CATEGORIES_ONLY=0

usage() {
  cat <<'EOF'
Usage:
  ./run_data_tests.sh
  ./run_data_tests.sh --category play
  ./run_data_tests.sh --category storage --category ai
  ./run_data_tests.sh --suite HomeViewModelTests
  ./run_data_tests.sh --suite HomeViewModelTests --suite DeckViewModelMutationTests
  ./run_data_tests.sh --simulator-id <DEVICE_ID>
  ./run_data_tests.sh --boot-default
  ./run_data_tests.sh --list
  ./run_data_tests.sh --list-categories

Behavior:
  - Runs data-flow XCTest suites serially.
  - Uses one simulator destination only.
  - Does not auto-boot a simulator unless you pass --boot-default.
  - Builds once with build-for-testing, then runs suites with test-without-building.

Options:
  --category <Name>       Run one or more suite categories.
  --suite <SuiteName>     Run only one or more named suites.
  --simulator-id <ID>     Use a specific booted simulator device ID.
  --boot-default          Boot the first available iPhone simulator if none is booted.
  --skip-build            Skip build-for-testing and only run test-without-building.
  --list                  Print available suites and exit.
  --list-categories       Print available categories and their suites.
  --help                  Show this help text.
EOF
}

print_suites() {
  printf '%s\n' "${ALL_SUITES[@]}"
}

print_categories() {
  cat <<'EOF'
ai: AIProviderStoreTests, AIJobSessionStoreTests, AIGenerationSessionStoreTests, AIWorkspaceCoordinatorTests, MatchConversionPipelineTests
authoring: CreateDeckViewModelTests, MatchQualityAndReadinessTests
decks: DeckViewModelMutationTests, DeckCardConversionRequestTests, DeckConversionPersistenceTests
home: HomeViewModelTests
library: LibraryViewModelMutationTests
play: DeckPlayModeSettingsStoreTests, PlaySessionPersistenceServiceTests
storage: DeckSharingManagerTests, StorageAndCleanupTests
EOF
}

fail() {
  echo "Error: $*" >&2
  exit 1
}

validate_suite_name() {
  local suite_name="$1"
  local known_suite

  for known_suite in "${ALL_SUITES[@]}"; do
    if [[ "$known_suite" == "$suite_name" ]]; then
      return 0
    fi
  done

  fail "Unknown suite '$suite_name'. Use --list to see the supported suites."
}

validate_category_name() {
  local category_name="$1"
  local known_category

  for known_category in "${CATEGORY_ORDER[@]}"; do
    if [[ "$known_category" == "$category_name" ]]; then
      return 0
    fi
  done

  fail "Unknown category '$category_name'. Use --list-categories to see the supported categories."
}

category_suites() {
  local category_name="$1"

  case "$category_name" in
    ai)
      printf '%s\n' "${CATEGORY_AI_SUITES[@]}"
      ;;
    authoring)
      printf '%s\n' "${CATEGORY_AUTHORING_SUITES[@]}"
      ;;
    decks)
      printf '%s\n' "${CATEGORY_DECKS_SUITES[@]}"
      ;;
    home)
      printf '%s\n' "${CATEGORY_HOME_SUITES[@]}"
      ;;
    library)
      printf '%s\n' "${CATEGORY_LIBRARY_SUITES[@]}"
      ;;
    play)
      printf '%s\n' "${CATEGORY_PLAY_SUITES[@]}"
      ;;
    storage)
      printf '%s\n' "${CATEGORY_STORAGE_SUITES[@]}"
      ;;
    *)
      fail "Unsupported category '$category_name'."
      ;;
  esac
}

dedupe_requested_suites() {
  local suite_name
  typeset -A seen_suites=()
  typeset -a deduped_suites=()

  for suite_name in "${REQUESTED_SUITES[@]}"; do
    if [[ -z "${seen_suites[$suite_name]-}" ]]; then
      seen_suites[$suite_name]=1
      deduped_suites+=("$suite_name")
    fi
  done

  REQUESTED_SUITES=("${deduped_suites[@]}")
}

expand_requested_categories() {
  local category_name
  local suite_name

  for category_name in "${REQUESTED_CATEGORIES[@]}"; do
    while IFS= read -r suite_name; do
      [[ -n "$suite_name" ]] || continue
      REQUESTED_SUITES+=("$suite_name")
    done < <(category_suites "$category_name")
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --category)
        [[ $# -ge 2 ]] || fail "--category requires a category name."
        validate_category_name "$2"
        REQUESTED_CATEGORIES+=("$2")
        shift 2
        ;;
      --suite)
        [[ $# -ge 2 ]] || fail "--suite requires a suite name."
        validate_suite_name "$2"
        REQUESTED_SUITES+=("$2")
        shift 2
        ;;
      --simulator-id)
        [[ $# -ge 2 ]] || fail "--simulator-id requires a device identifier."
        SIMULATOR_ID="$2"
        shift 2
        ;;
      --boot-default)
        BOOT_DEFAULT_SIMULATOR=1
        shift
        ;;
      --skip-build)
        SKIP_BUILD=1
        shift
        ;;
      --list)
        LIST_ONLY=1
        shift
        ;;
      --list-categories)
        LIST_CATEGORIES_ONLY=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        fail "Unknown argument '$1'. Use --help for usage."
        ;;
    esac
  done
}

booted_simulator_ids() {
  PATH="$XCODE_PATH" DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" \
    xcrun simctl list devices booted | awk -F '[()]' '/Booted/ { print $2 }'
}

pick_default_iphone_id() {
  PATH="$XCODE_PATH" DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" \
    xcrun simctl list devices available | awk -F '[()]' '/iPhone/ && /Shutdown|Booted/ { print $2; exit }'
}

resolve_simulator_id() {
  local booted_ids
  local booted_count
  local default_id

  if [[ -n "$SIMULATOR_ID" ]]; then
    return 0
  fi

  booted_ids=("${(@f)$(booted_simulator_ids)}")
  booted_count=${#booted_ids[@]}

  if [[ "$booted_count" -eq 1 ]]; then
    SIMULATOR_ID="$booted_ids[1]"
    return 0
  fi

  if [[ "$booted_count" -gt 1 ]]; then
    fail "More than one simulator is booted. Pass --simulator-id to choose exactly one."
  fi

  if [[ "$BOOT_DEFAULT_SIMULATOR" -eq 0 ]]; then
    fail "No booted simulator found. Boot one in Xcode first, or rerun with --boot-default."
  fi

  default_id="$(pick_default_iphone_id)"
  [[ -n "$default_id" ]] || fail "Could not find an available iPhone simulator to boot."

  echo "Booting simulator $default_id ..."
  PATH="$XCODE_PATH" DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcrun simctl boot "$default_id" >/dev/null 2>&1 || true
  PATH="$XCODE_PATH" DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" xcrun simctl bootstatus "$default_id" -b
  SIMULATOR_ID="$default_id"
}

build_for_testing() {
  echo "Building tests once into $DERIVED_DATA_PATH ..."
  PATH="$XCODE_PATH" DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" \
    xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -destination 'generic/platform=iOS Simulator' \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      CODE_SIGNING_ALLOWED=NO \
      build-for-testing
}

run_suite() {
  local suite_name="$1"

  echo
  echo "Running $suite_name on simulator $SIMULATOR_ID ..."

  PATH="$XCODE_PATH" DEVELOPER_DIR="$XCODE_DEVELOPER_DIR" \
    xcodebuild \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration Debug \
      -destination "id=$SIMULATOR_ID" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      CODE_SIGNING_ALLOWED=NO \
      -parallel-testing-enabled NO \
      -only-testing:"QuizFlashTests/$suite_name" \
      test-without-building
}

main() {
  local suite_name
  local suite_failures=0

  parse_args "$@"

  if [[ "$LIST_ONLY" -eq 1 ]]; then
    print_suites
    exit 0
  fi

  if [[ "$LIST_CATEGORIES_ONLY" -eq 1 ]]; then
    print_categories
    exit 0
  fi

  if [[ "${#REQUESTED_CATEGORIES[@]}" -gt 0 ]]; then
    expand_requested_categories
  fi

  if [[ "${#REQUESTED_SUITES[@]}" -eq 0 ]]; then
    REQUESTED_SUITES=("${ALL_SUITES[@]}")
  fi

  dedupe_requested_suites

  resolve_simulator_id

  echo "Using simulator $SIMULATOR_ID"
  echo "Suites: ${REQUESTED_SUITES[*]}"

  if [[ "$SKIP_BUILD" -eq 0 ]]; then
    build_for_testing
  fi

  for suite_name in "${REQUESTED_SUITES[@]}"; do
    if ! run_suite "$suite_name"; then
      ((suite_failures += 1))
    fi
  done

  echo
  if [[ "$suite_failures" -eq 0 ]]; then
    echo "All requested data-flow test suites passed."
    exit 0
  fi

  echo "$suite_failures suite(s) failed."
  exit 1
}

main "$@"
