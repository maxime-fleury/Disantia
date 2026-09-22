#!/usr/bin/env bash
# Build the Windows release: build/windows/Disantia.exe plus its .pck.
#
#   tools/export_windows.sh
#   GODOT=/path/to/godot tools/export_windows.sh
#
# This is a *release* export, so you get exactly two files: the windowed
# Disantia.exe and the Disantia.pck it loads. Windows gives a windowed exe no
# console, so its stdout is invisible in a terminal — but redirection still works,
# which is enough to run the suite against the shipped binary:
#
#   ./build/windows/Disantia.exe --headless -- --selftest > log.txt 2>&1
#
# The `debug/export_console_wrapper=1` option in the preset only takes effect for
# `--export-debug`, which is the export to use when you want Disantia.console.exe
# and a live console window.
#
# Godot will not create the output directory itself, which is the one thing that
# trips up a fresh `--export-release` on the command line.
set -euo pipefail

GODOT="${GODOT:-godot}"
PRESET="Windows"
OUT_DIR="build/windows"
OUT_EXE="$OUT_DIR/Disantia.exe"

cd "$(dirname "$0")/.."

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Godot not found. Set GODOT=/path/to/godot and try again." >&2
	exit 1
fi

mkdir -p "$OUT_DIR"
# build/ lives inside the project, so without this the importer treats the
# exported binaries as project assets and litters the folder with .import files.
touch build/.gdignore

echo "Importing assets ..."
# An import pass first, and not as a formality: the export ships *imported* resources, so a file
# added since the last time the editor was open is a file the export quietly leaves out — and the
# symptom is a character who does not speak rather than a build that fails.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

echo "Exporting preset '$PRESET' to $OUT_EXE ..."
"$GODOT" --headless --path . --export-release "$PRESET" "$OUT_EXE"
echo "Done: $(du -sh "$OUT_DIR" | cut -f1) in $OUT_DIR"
ls -1 "$OUT_DIR"
