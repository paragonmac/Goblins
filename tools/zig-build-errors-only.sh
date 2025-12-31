#!/usr/bin/env sh
set -eu

# Print only Zig compiler/linker errors (plus a tiny bit of context) and exit with the
# correct status code so JetBrains marks the build failed.
#
# Usage: tools/zig-build-errors-only.sh [zig build args...]

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

out_file="$(mktemp)"
trap 'rm -f "$out_file"' EXIT

# Run zig build, capture all output, and preserve zig's exit status.
set +e
zig build "$@" >"$out_file" 2>&1
status=$?
set -e

# Zig emits several error shapes:
#   path/file.zig:line:col: error: ...
#   error: undefined symbol: ...
#   error: the following command failed ...
# We'll show:
#   - per-file compile errors with 2 lines of context
#   - top-level 'error:' lines (linker, build system) with up to 4 lines of context
(
  grep -E -n -A2 "\.zig:[0-9]+:[0-9]+: error:" "$out_file" || true
  grep -n -E -A4 "^error:" "$out_file" || true
) | sed '/^--$/d'

exit "$status"
