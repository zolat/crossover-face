# Roadmap

**Current:** done — the per-ring gate has landed and is measured.

- [x] Phase 0 — baseline the frame cost on a fresh simulator
- [x] Phase 1a — cost the skipped frame, which nothing measured before
- [~] Phase 1b-1e — dropped on the measurement; see below
- [x] Phase 2a — memoise DotGrid.markedDot()
- [x] Phase 3 — redraw only the rings that changed
- [~] Phase 2b — dot-loop micro-hoists; not taken, see below

Plan: `~/.claude/plans/can-you-review-for-stateless-puffin.md`

## What the measurements settled

Same-load A/B: a temporary `const` in `FrameGate.plan()` reproduced the old whole-frame
behaviour, and the two legs were run back to back on the shipped code. Absolutes run well
above the figures in `2ec08e3` — a slower machine, and a second simulator competing for it —
and they moved by 20% between runs of identical code, which is exactly why the pairs are
what to read and a figure from another day is not.

| rings | whole-frame gate | per-ring gate | skipped |
|---|---|---|---|
| seconds + temperature | 89ms avg / 115 worst | **31ms avg / 97 worst** | 1% -> 0% |
| defaults | 85ms avg / 118 worst | **70ms avg / 94 worst** | 82% -> 81% |

**Phase 1 was aimed at the wrong thing, and 1a is what proved it.** The plan reasoned that
the preamble every frame pays before the gate decides — four sources read, spans, marks and
over flags built, a print compared — was the face's most-executed and least-examined code.
It is: at default rings 80% of frames do nothing else. It is also **0-1ms of a 70ms frame**.
So removing duplicate sensor reads (1b/1c) and putting a TTL on the weather read (1e) are
each worth under a millisecond; 1e in particular traded a semantic change — a temperature up
to 30s stale — for that, and is dropped rather than banked. 1a stays: it is the only figure
that will notice if the preamble ever grows.

1d landed in part, and had to. The two prints are preallocated and `FrameGate.copy()` keeps
values rather than the caller's array — not for the microsecond, but because the gate
storing a reference to a buffer the view refills would compare an array with itself and
freeze the face to one draw per cap. `spans`, `overs` and `markers` still allocate per
frame; at ≤1ms that is not worth the churn of changing.

**Phase 2b is not taken.** Splitting the dot loop on `turned` duplicates the loop body, and
the loop now runs on one ring in five frames out of six rather than on four rings every
frame. The cost it addresses shrank by more than the change would save.

## Left on the table

- **The repair cadence is the remaining lever.** `MAX_SKIPS = 5` means one frame in six is
  a full clear and redraw, and in the seconds configuration that single frame is now most
  of what the face costs. It is set where it is because it inherits the old cap's promise —
  damage drawn over the face from outside is gone within a few seconds. Raising it trades
  that promise for frame time and is a product decision, not a technical one.
- **The hand-backing coverage bitset**, worth ~4ms of a full redraw but only with backing
  on, which this configuration does not use.
- **On-watch verification of the partial redraw.** The simulator cannot answer whether the
  Dc handed to `onUpdate` holds what was last presented. `HOLD` and the two-slot mark erase
  are written to be correct either way, but only the watch can confirm it: `make install`,
  then watch across a minute boundary and a drift step for tearing or a stale ring.
- **Simulator screenshots are unavailable in this environment.** `screencapture -l` on the
  simulator's own window id returns *could not create image from window* with the display
  awake, which is the missing-Screen-Recording-permission signature rather than anything in
  the tooling. Granting it to the terminal restores `sim_screenshot`.
- **`Drift.PHASES` is a `const` array of arrays**, the pattern `DotGrid.ARMS` and
  `Palette.THEMES` are flattened to avoid because it resolves in the simulator and comes
  back empty on the watch. It evidently resolves today — an empty `PHASES` would divide by
  zero in `phaseFor` on every frame — so this is a latent-pattern flag, worth confirming
  during the on-watch check and flattening in its own commit if it does not hold.

---

# Previously: the simulator as typed tool calls (complete)


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
