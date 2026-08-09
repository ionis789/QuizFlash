#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/import_ai_lab_sources.sh [--device UDID|booted] FILE [...]

Moves local source files into the active iOS Simulator using the system-owned
destinations consumed by QuizFlash's normal pickers:
  - PDF files -> Files / On My iPhone / QuizFlash AI Lab
  - Images    -> Photos

Options:
  --device VALUE  Simulator UDID or "booted". Default: booted
  -h, --help      Show this help.

Examples:
  Scripts/import_ai_lab_sources.sh ~/Downloads/document.pdf
  Scripts/import_ai_lab_sources.sh --device booted ~/Downloads/*.pdf
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '==> %s\n' "$*"
}

device="booted"
source_files=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      [[ $# -ge 2 ]] || die "--device requires a value"
      device="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      source_files+=("$@")
      break
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      source_files+=("$1")
      shift
      ;;
  esac
done

[[ ${#source_files[@]} -gt 0 ]] || die "provide at least one PDF or image"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi

command -v xcrun >/dev/null 2>&1 || die "xcrun is unavailable"
xcrun simctl list devices | grep -F "$device" >/dev/null 2>&1 || {
  [[ "$device" == "booted" ]] || die "simulator not found: $device"
}

pdf_files=()
image_files=()
for source_file in "${source_files[@]}"; do
  [[ -f "$source_file" ]] || die "file not found: $source_file"
  filename="$(basename "$source_file")"
  extension="$(printf '%s' "${filename##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$extension" in
    pdf)
      pdf_files+=("$source_file")
      ;;
    jpg|jpeg|png|heic|heif|tif|tiff|gif)
      image_files+=("$source_file")
      ;;
    *)
      die "unsupported source type: $source_file"
      ;;
  esac
done

unique_destination() {
  local directory="$1"
  local filename="$2"
  local stem="$filename"
  local extension=""
  local candidate
  local suffix=2

  if [[ "$filename" == *.* ]]; then
    stem="${filename%.*}"
    extension=".${filename##*.}"
  fi

  candidate="$directory/$filename"
  while [[ -e "$candidate" ]]; do
    candidate="$directory/$stem-$suffix$extension"
    suffix=$((suffix + 1))
  done
  printf '%s' "$candidate"
}

if [[ ${#pdf_files[@]} -gt 0 ]]; then
  files_group=""
  while IFS=$'\t' read -r group_identifier group_path; do
    if [[ "$group_identifier" == "group.com.apple.FileProvider.LocalStorage" ]]; then
      files_group="$group_path"
      break
    fi
  done < <(xcrun simctl get_app_container "$device" com.apple.DocumentsApp groups)

  [[ -n "$files_group" ]] || die "could not locate the simulator Files storage"
  pdf_destination="$files_group/File Provider Storage/QuizFlash AI Lab"
  mkdir -p "$pdf_destination"

  for pdf_file in "${pdf_files[@]}"; do
    destination="$(unique_destination "$pdf_destination" "$(basename "$pdf_file")")"
    /usr/bin/ditto "$pdf_file" "$destination"
    log "PDF -> Files / On My iPhone / QuizFlash AI Lab / $(basename "$destination")"
  done

  xcrun simctl terminate "$device" com.apple.DocumentsApp >/dev/null 2>&1 || true
  xcrun simctl launch "$device" com.apple.DocumentsApp >/dev/null
fi

if [[ ${#image_files[@]} -gt 0 ]]; then
  xcrun simctl addmedia "$device" "${image_files[@]}"
  log "${#image_files[@]} image(s) -> Photos"
fi

log "Transfer complete"
