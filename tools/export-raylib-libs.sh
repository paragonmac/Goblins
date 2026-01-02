#!/usr/bin/env sh
set -eu

# Export raylib artifacts/headers into ./libs for convenience.
# Not required to build (we use the raylib-zig dependency), but useful if you
# want a local "libs" folder like older setups.

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p libs/raylib/lib libs/raylib/include

# Ensure cache exists.
zig build >/dev/null

# Find newest raylib static lib in the local build cache.
raylib_a="$(find .zig-cache -type f -name 'libraylib.a' -print 2>/dev/null | xargs -r ls -t 2>/dev/null | head -n 1 || true)"
if [ -z "$raylib_a" ] || [ ! -f "$raylib_a" ]; then
	echo "Could not find libraylib.a under .zig-cache/. Try running 'zig build' first." >&2
	exit 1
fi

cp -f "$raylib_a" libs/raylib/lib/libraylib.a

echo "Exported: $raylib_a -> libs/raylib/lib/libraylib.a"

# Best-effort export of common headers if present in the cache.
for h in raylib.h raymath.h rlgl.h rcamera.h raygui.h; do
	p="$(find .zig-cache -type f -name "$h" -print 2>/dev/null | head -n 1 || true)"
	if [ -n "$p" ] && [ -f "$p" ]; then
		cp -f "$p" "libs/raylib/include/$h"
		echo "Exported: $p -> libs/raylib/include/$h"
	fi
done

echo "Done. (These files are local-only unless you commit them.)"
