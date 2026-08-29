# Roadmap

**Current:** done — all phases complete; `.mcp.json` needs approval + a session restart
before the tools are callable.

`tools/simctl` + a project-scoped MCP server (`tools/sim_mcp.py`) so simulator work —
screenshots, settings, structured test results — is typed tool calls rather than
script-scraping and GUI clicking, and so parallel sessions get their own instance instead
of queueing on the lock.

Plan: `~/.claude/plans/is-the-ciq-simulator-cuddly-kahan.md`

- [x] Phase 0 — Prove instance isolation. `TMPDIR` + `HOME` + `SHELL_SERVER_PORT`, plus a
      pinned `shell` wrapper, give a fully independent simulator.
- [x] Phase 1 — Settings codec. Byte-exact `.SET` round trip, schema-validated.
- [x] Phase 2 — Capture. CoreGraphics through `ctypes` (no pyobjc), per-instance by pid,
      slept-display detection.
- [x] Phase 3 — Runner and instance lifecycle. Two checkouts ran the 60-test suite
      concurrently, both green, neither touching the lock.
- [x] Phase 4 — MCP layer: 8 tools over stdio, `.mcp.json`, `CLAUDE.md`.

## What was proved, not assumed

- Two simulators coexisted on separate ports with separate device filesystems and
  settings; a pinned sideload reached the intended one; teardown left no strays.
- `make test-simctl` — 37 tests. `make test-lock` — unchanged, still passes.
  `make test` — 60/60 on the shared simulator *and* inside an isolated instance.
- A capture's luminance is **not** the 10% budget figure: it includes the simulator's
  drawing of the physical hands (11.17% as captured against 5.43% without them).

## Known limits

- macOS only: window capture is `screencapture` plus CoreGraphics.
- Only whole-number settings are handled — every property this face has is a list.
- One instance per checkout. Two sessions in the *same* checkout still share `bin/`,
  so they would race on build output rather than on the simulator.
