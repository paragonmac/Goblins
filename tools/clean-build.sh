#!/usr/bin/env sh
set -eu

# Safe clean: only removes Zig build outputs.
# Does NOT touch editor config (.vscode/) or local folders like libs/.

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

rm -rf .zig-cache zig-cache zig-out

echo "Removed: .zig-cache/ zig-cache/ zig-out/"
