#!/usr/bin/env bash
# Rebuild the web export and (optionally) serve it.
#
#   tools/export_web.sh          export only
#   tools/export_web.sh --serve  export, then serve on http://127.0.0.1:8791/
#
# Godot will not create the output directory itself, which is the one thing that
# trips up a fresh `--export-release` on the command line.
set -euo pipefail

GODOT="${GODOT:-godot}"
PRESET="Web"
OUT_DIR="build/web"
PORT="${PORT:-8791}"

cd "$(dirname "$0")/.."

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "Godot not found. Set GODOT=/path/to/godot and try again." >&2
	exit 1
fi

mkdir -p "$OUT_DIR"
# build/ lives inside the project, so without this the importer treats the
# exported icons as project assets and litters the folder with .import files.
touch build/.gdignore

echo "Exporting preset '$PRESET' to $OUT_DIR/index.html ..."
"$GODOT" --headless --path . --export-release "$PRESET" "$OUT_DIR/index.html"
echo "Done: $(du -sh "$OUT_DIR" | cut -f1) in $OUT_DIR"

if [[ "${1:-}" == "--serve" ]]; then
	exec python tools/serve_web.py "$PORT"
fi
