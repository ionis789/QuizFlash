#!/usr/bin/env python3
import argparse
import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STRINGS_ROOT = ROOT / "QuizFlash"
TSV_PATH = Path(__file__).resolve().parent / "localization_matrix.tsv"
LANGUAGE_FILES = {
    "en": STRINGS_ROOT / "en.lproj" / "Localizable.strings",
    "ro": STRINGS_ROOT / "ro.lproj" / "Localizable.strings",
    "ru": STRINGS_ROOT / "ru.lproj" / "Localizable.strings",
}
ENTRY_PATTERN = re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$')


def unescape_strings_value(value: str) -> str:
    return (
        value
        .replace(r"\\", "\\")
        .replace(r"\"", '"')
        .replace(r"\n", "\n")
    )


def escape_strings_value(value: str) -> str:
    return (
        value
        .replace("\\", r"\\")
        .replace('"', r"\"")
        .replace("\n", r"\n")
    )


def load_strings(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//") or line.startswith("/*") or line.startswith("*") or line.startswith("*/"):
            continue
        match = ENTRY_PATTERN.match(line)
        if not match:
            continue
        key = unescape_strings_value(match.group(1))
        value = unescape_strings_value(match.group(2))
        values[key] = value
    return values


def write_strings(path: Path, values: dict[str, str]) -> None:
    lines = [
        f"\"{escape_strings_value(key)}\" = \"{escape_strings_value(values[key])}\";"
        for key in sorted(values.keys(), key=str.casefold)
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def export_tsv(output_path: Path) -> None:
    language_maps = {language: load_strings(path) for language, path in LANGUAGE_FILES.items()}
    all_keys = sorted({key for mapping in language_maps.values() for key in mapping.keys()}, key=str.casefold)

    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, delimiter="\t")
        writer.writerow(["key", "en", "ro", "ru"])
        for key in all_keys:
            writer.writerow([
                key,
                language_maps["en"].get(key, ""),
                language_maps["ro"].get(key, ""),
                language_maps["ru"].get(key, ""),
            ])


def import_tsv(input_path: Path) -> None:
    language_maps = {"en": {}, "ro": {}, "ru": {}}
    with input_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            key = (row.get("key") or "").strip()
            if not key:
                continue
            for language in ("en", "ro", "ru"):
                value = row.get(language, "")
                if value is None:
                    value = ""
                language_maps[language][key] = value

    for language, path in LANGUAGE_FILES.items():
        write_strings(path, language_maps[language])


def main() -> None:
    parser = argparse.ArgumentParser(description="Export or import QuizFlash localization keys as TSV.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    export_parser = subparsers.add_parser("export", help="Write the current strings files into a TSV matrix.")
    export_parser.add_argument("--output", type=Path, default=TSV_PATH)

    import_parser = subparsers.add_parser("import", help="Write the TSV matrix back into the strings files.")
    import_parser.add_argument("--input", type=Path, default=TSV_PATH)

    args = parser.parse_args()
    if args.command == "export":
        export_tsv(args.output)
    else:
        import_tsv(args.input)


if __name__ == "__main__":
    main()
