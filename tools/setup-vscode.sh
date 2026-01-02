#!/usr/bin/env sh
set -eu

# Create local VS Code config from the committed template.
# This repo intentionally does not commit .vscode/.

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p .vscode

for f in tasks.json launch.json settings.json; do
	if [ -f ".vscode.example/$f" ]; then
		cp -f ".vscode.example/$f" ".vscode/$f"
	fi
done

echo "Wrote .vscode/ from .vscode.example/"
