# Repository Guidelines

## Project Structure & Module Organization

A Monkey C watch face targets the Garmin Instinct Crossover AMOLED. Lifecycle and view code live directly under `source/`; domain data is in `source/data/`, geometry and ring mapping in `source/matrix/`, drawing in `source/render/`, settings UI in `source/settings/`, and tests in `source/tests/`. Garmin resources live under `resources/`. Python simulator, mockup, luminance, and MTP helpers are under `tools/`. Treat `bin/` and `build/` as generated output.

## Build, Test, and Development Commands

- `make build` compiles a debug `.prg` for `instinctcrossoveramoled`; strict type checking and warnings are enabled.
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

Add Monkey C tests to `source/tests/MatrixTest.mc` with `(:test)` and descriptive `camelCase` names. Add Python `test_*` methods to `tools/simctl_test.py`. Run all three test targets before submission. For visual or performance changes, inspect the face and re-measure luminance or frame timing. Trust `make test`'s parsed summary, not raw `monkeydo` exit status.

## Commit & Pull Request Guidelines

Recent commits use imperative, sentence-style subjects such as `Centre each forecast block in its hour slot`. Keep commits focused and explain design constraints or measurements in the body. Pull requests should summarize user-visible behavior, list verification commands, link relevant issues, and include simulator screenshots for visual changes.

## Workflow & Security

Create feature branches in `.claude/worktrees/<name>`; keep `main` buildable. For emulator work, prefer the `crossover-simulator` MCP and omit `instance` to use Codex's private, checkout-specific simulator. Never pass `instance="shared"` unless explicitly coordinating shared use with Claude; Make targets lock that shared simulator. Call `sim_release` after a loaded session. Never commit signing keys (`*.der`, `*.pem`) or generated artifacts.
