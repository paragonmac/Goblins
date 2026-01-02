# Goblinoria

Zig + raylib game experiment.

## Requirements

- Zig `0.15.2` (see `build.zig.zon`)
- A working C toolchain for your platform (needed by raylib)

The project uses Zig package dependencies (see `build.zig.zon`). On first build, Zig may download dependencies.

## Build

From the repo root:

- Build: `zig build`
- Run: `zig build run`
- Test: `zig build test`

If you want to prefetch deps (optional):

- `zig build --fetch`

## VS Code setup (optional)

This repo does **not** commit `.vscode/` (it’s user/editor specific), but a working template is provided.

- One-time setup:
  - `tools/setup-vscode.sh`

This will create/update `.vscode/` from `.vscode.example/`.

## Cleaning build outputs (safe)

Avoid using `git clean -fdx` (it deletes ignored folders like `.vscode/` too).

Use:

- `tools/clean-build.sh`

This only removes Zig build output folders (`.zig-cache/`, `zig-out/`).
