# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A Connect IQ watch face for the **Garmin Instinct Crossover AMOLED**, written in Monkey C. The
face is a dot-matrix field where the data *is* the background: four concentric rings of
~1,100 dots, each dot coloured by the source its ring is assigned to.

`README.md` is the authority on toolchain setup, MTP sideloading and design rationale. This file
covers the working knowledge that spans files and is easy to break.

## Commands

```sh
make build      # debug .prg for the simulator
make sim        # build, start the simulator if needed, sideload, stream println
make test       # build with -t, run the 48-test suite (takes the simulator lock)
make test-lock  # self-test tools/sim_lock.sh
make package    # signed .iq for the store
make install    # build, verify MTP mode, push straight to the watch
make push       # build and push, skipping the checks
make reveal     # fallback: open OpenMTP for a manual drag
make sdk-info   # resolved SDK path, device and key
```

Run one test. `make test` must have run at least once first — it builds the test `.prg`
(`bin/` is gitignored) and starts the simulator, both of which `monkeydo` needs. The test
name must be **module-qualified**; a bare name errors out:

```sh
SDK=$(connect-iq-sdk-manager sdk current-path)
"${SDK}bin/monkeydo" bin/CrossoverFace-test.prg instinctcrossoveramoled \
    -t MatrixTest.driftDutyCycleIsOnePhaseInFour
```

Design loop, no compile needed:

```sh
python3 tools/mockup.py [outdir]        # default build/mockups
python3 tools/luminance.py <face.png>   # measure against the 10% AMOLED budget
```

## Parallel sessions share three things

Several agents work this repo at once, in worktrees under `.claude/worktrees/`.
Three resources are shared across all of them, and each one has bitten this project.

**The compiler will eat your neighbour's branch.** `monkeyc` globs `source/**` *recursively
from the project root*, so without `base.sourcePath = source` in `monkey.jungle` a build at
the repo root compiles every worktree's copy of the face alongside its own. It fails as a
wall of `Redefinition of ...` naming files on a sibling branch, which looks like your tree is
broken. **Never remove that line.**

**The simulator is a singleton.** One per machine, one persisted app-data store, and
`monkeydo` sideloads into it by device id. Two sessions doing that at once take each other's
run down — and the loser prints a bare `TESTS FAILED` with *no output*, which is
indistinguishable from a real failure. `make test` and `make sim` serialise on
`tools/sim_lock.sh` (a lock directory outside the repo, holding the owner's PID so a dead
session's lock can be proved stale). `sim` holds it for as long as it stays attached, because
an attached `monkeydo` owns the simulator and would otherwise silently kill test runs.

> The lock only covers the make targets. A hand-rolled `monkeydo` slips past it — so run the
> simulator through `make`, and never `pkill -f monkeydo`, which kills every session's.

If a run does die, `make test` now says so rather than blaming the tests: no `Ran N tests`
line means contention, and it names whatever is still attached. **Re-run before believing a
bare failure.**

**The watch is a singleton too.** `make install` / `make push` claim the USB interface, and
only one process may hold it. Nothing serialises that yet — coordinate by hand.

Editing `Makefile`, `monkey.jungle` or `CLAUDE.md` changes them under every session
immediately, worktrees included. That is usually what you want for a fix like the ones above,
but say so rather than letting another agent discover it mid-run.

### Command gotchas

- **There is no lint or typecheck step.** `monkey.jungle` sets `project.typecheck = strict` and
  the Makefile passes `-w`, so a clean `make build` *is* the type check. Don't go looking for one.
- **`monkeydo` exits non-zero even when every test passes**, which is why `make test` greps for
  `^PASSED` and ignores the exit code. Never judge a raw `monkeydo` run by its status code — read
  the summary line.
- **A killed simulator looks like a test failure.** If `make test` prints nothing but
  `TESTS FAILED`, the simulator died mid-run. The target now diagnoses this itself — no
  `Ran N tests` line means contention, not a bug — but re-run before believing it either way.
- **The watch must be in MTP mode and OpenMTP must not be running.** Only one process may
  claim the USB interface; `make push` quits OpenMTP for you. `idProduct 0x5246` (21062) is MTP,
  `0x0003` is Garmin's proprietary mode, which cannot be written to — answer **yes** to
  *Use MTP?* on the watch. Note that `ioreg` prints `idProduct` *before* `idVendor`, so a
  `grep -A` window anchored on the vendor will silently miss it.
- **`luminance.py` wants a raw 390×390 face render**, not the contact sheets in `build/mockups/`
  — a sheet measures meaninglessly high. `mockup.py` prints per-face figures itself.

## Architecture

Draw path: `CrossoverApp` → `CrossoverView` (picks the palette for the current power mode; does
no drawing) → `MatrixRenderer.draw(dc, spans, palette, ramp, backing)`.

Data path: `StatMap.spans()` → `Source.span()` → `WatchData` / `WeatherData`. Data modules are
pure queries and never draw; the renderer never learns where a number came from.

Geometry: `DotGrid` (the lattice, cached), `StatMap` (dot → ring + position — the mapping seam),
`Drift` (burn-in cycle), `HandBacking` (which dots sit under the physical hands).

### The frame budget dominates every decision here

~1,100 dots are drawn per `onUpdate` in interpreted bytecode against a hard watchdog. An earlier
version that computed each dot's ring and position inline **tripped the watchdog outright** and
the face would not load. The rule:

> Nothing is computed in the render loop that `DotGrid.build()` could compute once, and nothing
> calls out of the loop that could be an array lookup.

`DotGrid` caches parallel arrays (`xs`, `ys`, `positionOf`, `armOf`) built once per
rebuild; `MatrixRenderer` is a flat indexed walk. There is no `ringOf`: dots are stored grouped
by ring, so `ringStart` already says which ring an index belongs to. The single deliberate exception is
`StatMap.isLit()`, called per dot (~6ms/frame) so the lit test has one definition shared with the
tests. Current cost: avg 36ms, peak 44ms. **If you add per-dot work or raise the dot count,
re-measure** — wrap `onUpdate` in `System.getTimer()` and read `make sim` output.

Caching the field to a `BufferedBitmap` is not an option: 390×390 at 16bpp is ~304KB against a
128KB watch-face memory budget.

### What the memory budget actually measures

The 131,072-byte watch-face limit is a **runtime** one, and it is worth being precise because
the obvious wrong reading is alarming and has been made here already: comparing the size of a
built `.prg` against it. That comparison is meaningless.

- `monkeyc` does not enforce it at build time at all. A padded `watchface` `.prg` of **258KB**
  compiles without complaint (measured, no `-t`). File size is not the budget.
- A **debug** `.prg` is ~129KB and a **release** one (`-r`) is ~25KB. The whole difference is
  symbol tables — `-r` is documented as "strip debug information" — not code. Optimisation is
  not a lever: `-O 2`, `-O 3`, `-O 2z` and `-O 2p` all give the identical 25KB, which the
  default already reaches.
- What the face actually uses, read off `Diagnostics.summary()` on the device profile:
  **46k of 123k, about 37%**. Note the app is granted 123k rather than the nominal 128k.

The dominant runtime consumer is the `DotGrid` cache — four parallel arrays of one entry per
dot, **22,240 bytes at 1112 dots**, five bytes a slot. `theDotCacheFitsItsShareOfMemory`
measures it and fails if a fifth per-dot array appears. That test has to drop the arrays'
references before sampling: a rebuild in place frees each old array as the new one is assigned,
so measuring across `invalidate()` alone reports a delta of nothing and passes vacuously.

`make install` ships the debug build on purpose — symbolicated `CIQ_LOG` traces are worth more
than the flash on a face with a watchdog history. See the comment on `install:`.

### Config.reload() ordering is load-bearing

`StatMap.load()` → `Palette.build()` → `DotGrid.build()`. Palette hues depend on the ring
assignments, so one without the other draws last session's colours. Anything that changes a
setting must go through `Config.reload()`, not a partial refresh. Nothing settable moves the
lattice any more, so `DotGrid.invalidate()` is now a safety net rather than a requirement —
but the rebuild it schedules must still land in `onLayout`, never `onStart`.

### Every source reports a span, not a level

`Source.span()` returns `[start, end]`, both 0.0–1.0. Levels are just `[0.0, value]`. This is why
temperature — a genuine range — needs no special case anywhere downstream.

`end < start` is **legal**: the temperature scale (0–60°C, one degree per minute mark) wraps
rather than clamps, so a sub-zero range runs from e.g. :55 round past twelve to :03.
`StatMap.isLit()` handles the wrap. Don't "fix" it by clamping — that silently misreports a
−5→3°C day as 0→3°C, and `subZeroWrapsBackPastTwelve` guards it.

### tools/mockup.py mirrors the Monkey C by hand

The Python mockup duplicates the lattice constants, `THEME`, `WEAK_*`/`LIFT`, `ARMS`, the
ring mapping and the hand geometry. It is not generated. **Any change to geometry or palette
must land in both**, and `MatrixTest.EXPECTED_DOTS` (1112) plus the luminance tests pin the two
implementations together so they cannot drift silently.

### Settings live in five places that must stay in step

Stored values are **list indices**, so `resources/properties.xml`, `resources/settings/settings.xml`,
`resources/strings/strings.xml`, the enums in `StatMap`/`Source`, and the label arrays in
`source/settings/SettingsMenu.mc` all have to agree. Seven properties today: `handBacking`,
`alwaysOnFill`, `dotRotation`, `ring1`–`ring4`.

`SettingsMenu.onShow()` refreshes sub-labels **by row index**, and `getItem()` on a wrong
index returns null rather than throwing — so adding or removing a row silently stops
refreshing the ones after it. `MatrixTest.MENU_VALUE_ROWS` is the guard; move it in the same
commit.

On-device settings exist because phone-side settings are unreliable for a sideloaded face;
`AppBase.getSettingsView()` is the sanctioned exception to "watch faces cannot take input".
`StatMap.readNumber()` falls back to the default for anything missing or out of range rather than
throwing. Menu sub-labels are refreshed in `onShow()` — Menu2 does not rebuild itself when a
sub-menu pops.

To change a setting in the simulator: **File → Edit Persistent Storage → Edit
Application.Properties**. Persisted values beat `properties.xml`, so a stale one survives a
rebuild until **Reset All App Data**.

### Dot rotation is a render choice, not a cached one

`StatMap.rotation` decides only whether `MatrixRenderer` indexes `DotGrid.armOf` per dot or
uses the one upright cross it hoists. Which way a cross *would* point is geometry, so it is
cached either way and toggling the setting needs no rebuild. Do not move this into
`DotGrid.build()`: it would cost a full ~1100-dot rebuild per toggle, and the next step from
there is making the ring mapping conditional again. `rotationDoesNotReachTheCache` is the
guard. Every orientation lights nine pixels, so neither setting moves the luminance.

### The 10% luminance budget

Garmin blanks an always-on face that exceeds 10% of screen luminance. Current design sits at
~4.8% active / ~4.6% always-on, ~5.7% worst case. `alwaysOnWorstCaseFitsBudget` asserts it in the
test suite; `tools/luminance.py` and the simulator's **File → View Screen Heat Map** measure it.

Awake and always-on share their *filled* colours and differ only in the unfilled tier
(`WEAK_ACTIVE` 0.55 vs `WEAK_ALWAYS_ON` 0.45). `Palette.LIFT` is 1.0 — scaling up would clamp
channels and shift hue rather than brighten.

There is a **third palette table**, `Palette.heldBack`, for always-on with the fills held back.
Nothing is lit in that mode, so the unfilled tier is the whole image rather than a backdrop, and
`WEAK_HELD_BACK` lifts it — written as `WEAK_ACTIVE`, not as a value, because the decision is to
match the awake field so the background does not shift on a wrist raise. It moves that frame from
~2.6% to ~3.2%, against ~4.6–5.0% for the same mode with its data shown. Staying clearly below
that data-shown figure, not the 10% budget, is the real bound on how far this tier may be lifted,
and `heldBackFillsCutAlwaysOnLuminance` is what holds the line.

### Device facts that constrain the design

390×390 round AMOLED, buttons only (**no touch**), 131,072-byte watch-face memory. A 21px hub and
two physical analogue hands (hour 131px, minute 176px reach, 28px wide, minute hand mid-grey
`0x808080`) sit over the glass — the grey minute hand is the real palette constraint. Hand and
display geometry is read from `~/.Garmin/ConnectIQ/Devices/instinctcrossoveramoled/simulator.json`;
keep it sourced from there rather than hard-coding new numbers.

Dots are **crosses, not squares** (2·DOT−1 = 9 lit pixels, not 25) — that is what buys ~1,100 dots
inside the luminance budget. `Drift`'s −2/+3 offsets are forced by the 10px pitch and 5px dot:
they are exactly DOT apart and consume exactly the slack, so a dot neither overlaps itself nor
lands on its neighbour. A symmetric ±3 breaks this; `driftDutyCycleIsOnePhaseInFour` catches it.

### Sideloading is automated — don't reintroduce the manual drag

`tools/mtp_push.py` drives OpenMTP's own MTP engine (`kalam.dylib`, an arm64 Go library inside
the app bundle) through ctypes, so `make install` pushes the `.prg` with no GUI. libmtp is not
an option: `libusb_claim_interface()` returns `-3` because macOS's Image Capture daemon holds
the interface, so `mtp-detect` finds the watch and still cannot open it.

Two traps live in that driver. The exported callbacks read `on_cb_result_t*`, which looks like
a pointer to a function pointer but is not — kalam calls the address it is handed, so `byref()`
aborts with SIGBUS at exactly the value passed. And a ctypes callback that gets garbage
collected while Go still holds it is a segfault, which is why they are kept on the instance.
The JSON contract is transcribed from OpenMTP's own unminified bindings in `app.asar`; if
OpenMTP ships a breaking change, re-read them there rather than guessing.

## Notes

- The signing key lives at `~/.Garmin/ConnectIQ/developer_key.der`, deliberately outside the repo.
  Never commit it — it cannot be reissued for apps already in the store.
- `bin/` and `build/` are gitignored build output.
- Avoid apostrophes anywhere in the project path; the Monkey C compiler fails on them.
- `README.md` currently contains a **stale duplicate** of its second half (from "## Frame budget"
  around line 326 onward). That copy predates the current settings work — it claims one setting
  and refers to `LayoutMenu.mc` and `StatMap.load()` reading properties directly. Trust the first
  copy and the code.
