# Repository Guidelines

## Project Structure & Module Organization

This Monkey C watch face targets the Instinct Crossover AMOLED and Epix 2 family. Core code lives under `source/`, split into `data/`, `matrix/`, `render/`, `settings/`, and `tests/`. Garmin resources live under `resources/`; device-specific lattice, hand, and resource overrides use the sibling `source-*` and `resources-*` directories. Python simulator, mockup, luminance, and MTP helpers are under `tools/`. Treat `bin/` and `build/` as generated output.

## Build, Test, and Development Commands

- `make build DEVICE=epix2` compiles a device-namespaced debug `.prg`; omit `DEVICE` for the Crossover. Strict type checking and warnings are enabled.
- `make test` compiles and runs the Monkey C test suite in the Garmin simulator.
- `make test-simctl` runs the Python `unittest` suite without a build or simulator.
- `make test-lock` validates simulator-lock behavior.
- `make sim` builds, launches the shared simulator, sideloads the face, and streams logs.
- `python3 tools/mockup.py` renders design mockups; use `python3 tools/luminance.py <390x390-face.png>` for AMOLED-budget checks.
- `make package` creates the signed store `.iq` artifact.

See `README.md` for Connect IQ SDK, Java, device-file, and signing-key setup.

## Coding Style & Naming Conventions

Use four-space indentation. Match Monkey C conventions: `PascalCase` modules, classes, and filenames; `camelCase` functions and variables; `UPPER_SNAKE_CASE` constants. Keep rendering loops allocation-free and avoid calls or repeated geometry calculations in per-dot hot paths. Python follows PEP 8-style conventions. No separate formatter or linter is configured; a warning-free `make build` is the lint/type-check gate.

## Testing Guidelines

Add Monkey C `(:test)` cases to `source/tests/MatrixTest.mc` and Python `test_*` methods to `tools/simctl_test.py`. Run all test targets and the affected device matrix before submission. For visual or performance changes, inspect the face and re-measure luminance or frame timing. Trust `make test`'s summary, not raw `monkeydo` exit status.

## Commit & Pull Request Guidelines

Recent commits use imperative, sentence-style subjects such as `Centre each forecast block in its hour slot`. Keep commits focused and explain design constraints or measurements in the body. Pull requests should summarize user-visible behavior, list verification commands, link relevant issues, and include simulator screenshots for visual changes.

## Workflow & Security

Create branches in `.claude/worktrees/<name>`; keep `main` buildable. Prefer the `crossover-simulator` MCP: omit `instance` to reuse the agent session's private simulator, including when moving between devices, and pass the same `device` through load, settings, screenshot, test, and release. Use a named instance only when two simulators must be visible concurrently. Call `sim_release` as soon as visual work is done; it stops the private simulator, and server shutdown is the fallback cleanup. Use `instance="shared"` only when explicitly coordinating with Claude; Make targets lock it. Never commit signing keys (`*.der`, `*.pem`) or generated artifacts.
