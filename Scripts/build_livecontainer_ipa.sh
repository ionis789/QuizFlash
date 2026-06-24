#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/build_livecontainer_ipa.sh [options]

Archives QuizFlash for generic iOS device, extracts QuizFlash.app from the
.xcarchive, places it under Payload/, and creates a LiveContainer-ready IPA.

Options:
  --output-dir PATH     Output folder. Default: ~/Downloads/app-ipa
  --prefix NAME         IPA name prefix. Default: quizflash-beta
  --configuration NAME  Xcode configuration. Default: Release
  --scheme NAME         Xcode scheme. Default: QuizFlash
  --project PATH        Xcode project. Default: QuizFlash.xcodeproj
  --archive-path PATH   Use an explicit .xcarchive path.
  --keep-existing-app   Do not delete existing Payload/QuizFlash.app first.
  --verbose             Show full xcodebuild output.
  -h, --help            Show this help.

Environment:
  XCODEBUILD_EXTRA_ARGS  Extra arguments appended to xcodebuild archive.

Examples:
  Scripts/build_livecontainer_ipa.sh
  Scripts/build_livecontainer_ipa.sh --output-dir "$HOME/Downloads/app-ipa"
  XCODEBUILD_EXTRA_ARGS='CODE_SIGNING_ALLOWED=NO' Scripts/build_livecontainer_ipa.sh
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

project="QuizFlash.xcodeproj"
scheme="QuizFlash"
configuration="Release"
app_name="QuizFlash"
output_dir="$HOME/Downloads/app-ipa"
ipa_prefix="quizflash-beta"
archive_path=""
keep_existing_app=0
verbose=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] || die "--output-dir requires a value"
      output_dir="$2"
      shift 2
      ;;
    --prefix)
      [[ $# -ge 2 ]] || die "--prefix requires a value"
      ipa_prefix="$2"
      shift 2
      ;;
    --configuration)
      [[ $# -ge 2 ]] || die "--configuration requires a value"
      configuration="$2"
      shift 2
      ;;
    --scheme)
      [[ $# -ge 2 ]] || die "--scheme requires a value"
      scheme="$2"
      shift 2
      ;;
    --project)
      [[ $# -ge 2 ]] || die "--project requires a value"
      project="$2"
      shift 2
      ;;
    --archive-path)
      [[ $# -ge 2 ]] || die "--archive-path requires a value"
      archive_path="$2"
      shift 2
      ;;
    --keep-existing-app)
      keep_existing_app=1
      shift
      ;;
    --verbose)
      verbose=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

cd "$repo_root"

[[ -d "$project" ]] || die "Xcode project not found: $project"

if [[ -z "$archive_path" ]]; then
  archive_day="$(date '+%Y-%m-%d')"
  archive_name="${app_name} $(date '+%d-%m-%Y, %H.%M').xcarchive"
  archive_dir="$HOME/Library/Developer/Xcode/Archives/$archive_day"
  archive_path="$archive_dir/$archive_name"

  if [[ -e "$archive_path" ]]; then
    archive_name="${app_name} $(date '+%d-%m-%Y, %H.%M.%S').xcarchive"
    archive_path="$archive_dir/$archive_name"
  fi
fi

mkdir -p "$(dirname "$archive_path")"
mkdir -p "$output_dir"

log "Archiving $scheme ($configuration) for Any iOS Device"

xcodebuild_args=(
  archive
  -project "$project"
  -scheme "$scheme"
  -configuration "$configuration"
  -destination "generic/platform=iOS"
  -archivePath "$archive_path"
)

if [[ "$verbose" -eq 0 ]]; then
  xcodebuild_args+=(-quiet)
fi

xcodebuild "${xcodebuild_args[@]}" ${XCODEBUILD_EXTRA_ARGS:-}

app_source="$archive_path/Products/Applications/$app_name.app"
[[ -d "$app_source" ]] || die "App bundle not found in archive: $app_source"

payload_dir="$output_dir/Payload"
app_destination="$payload_dir/$app_name.app"

log "Preparing Payload folder"
mkdir -p "$payload_dir"
if [[ "$keep_existing_app" -eq 0 ]]; then
  rm -rf "$app_destination"
fi
/usr/bin/ditto "$app_source" "$app_destination"

next_ipa_number() {
  local max_number=0
  local file
  local base
  local number

  shopt -s nullglob
  for file in "$output_dir"/"${ipa_prefix}"*.ipa; do
    base="$(basename "$file")"
    number="$(printf '%s' "$base" | sed -nE "s/^${ipa_prefix}([0-9]+)\\.ipa$/\\1/p")"
    if [[ -n "$number" && "$number" =~ ^[0-9]+$ && "$number" -gt "$max_number" ]]; then
      max_number="$number"
    fi
  done
  shopt -u nullglob

  printf '%s' "$((max_number + 1))"
}

ipa_number="$(next_ipa_number)"
ipa_path="$output_dir/${ipa_prefix}${ipa_number}.ipa"
while [[ -e "$ipa_path" ]]; do
  ipa_number="$((ipa_number + 1))"
  ipa_path="$output_dir/${ipa_prefix}${ipa_number}.ipa"
done

log "Creating IPA: $ipa_path"
(
  cd "$output_dir"
  rm -f "$ipa_path"
  /usr/bin/ditto -c -k --norsrc --keepParent "Payload" "$ipa_path"
)

log "Archive: $archive_path"
log "App: $app_destination"
log "IPA: $ipa_path"
