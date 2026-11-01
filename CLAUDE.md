# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A Connect IQ watch face for the **Garmin Instinct Crossover AMOLED** and the **Epix 2
family**, written in Monkey C. The face is a dot-matrix field where the data *is* the
background: four concentric rings of ~1,100-1,400 dots, each dot coloured by the source its
ring is assigned to.

The two halves of that list differ in one hardware fact with consequences everywhere: the
Crossover has **physical** analogue hands over the glass, and the Epix has none, so there the
face draws the hands out of its own dots. See *One face, five watches* below.

`README.md` is the authority on toolchain setup, MTP sideloading and design rationale. This file
covers the working knowledge that spans files and is easy to break.

## Commands

```sh
make build      # debug .prg for the simulator
make sim        # build, start the simulator if needed, sideload, stream println
make test       # build with -t, run the 152-test suite (takes the simulator lock)
make test-lock  # self-test tools/sim_lock.sh
make test-simctl # tests for tools/simctl (no simulator, no build needed)
make package    # signed .iq for the store
make install    # build, verify MTP mode, push straight to the watch
make push       # build and push, skipping the checks
make reveal     # fallback: open OpenMTP for a manual drag
make sdk-info   # resolved SDK path, device and key
```

**Every target takes `DEVICE=`**, defaulting to `instinctcrossoveramoled`. Build output is
namespaced by it — `bin/<device>/CrossoverFace.prg` — because a flat `bin/` let one watch's
build overwrite another's with nothing recording which it was for, and `make sim` would then
sideload a 390 face onto a 454 screen and look merely wrong rather than broken. The PRG
*stem* is deliberately unchanged, so `CROSSOVERFACE.SET` stays where every tool expects it.

```sh
make test DEVICE=epix2pro51mm    # the 454 lattice, drawn hands
make build DEVICE=epix2          # 416
make package                     # passes no -d: builds every manifest product
```

Run one test. `make test` must have run at least once first — it builds the test `.prg`
(`bin/` is gitignored) and starts the simulator, both of which `monkeydo` needs. The test
name must be **module-qualified**; a bare name errors out:

```sh
SDK=$(connect-iq-sdk-manager sdk current-path)
"${SDK}bin/monkeydo" bin/instinctcrossoveramoled/CrossoverFace-test.prg \
    instinctcrossoveramoled \
    -t MatrixTest.driftDutyCycleIsOnePhaseInFour
```

Design loop, no compile needed:

```sh
python3 tools/mockup.py [outdir] [device]   # default build/mockups, crossover
python3 tools/luminance.py <face.png>   # measure against the 10% AMOLED budget
```

## One face, five watches

`manifest.xml` lists five products and `monkey.jungle` gives each its own source path. Two
small modules are what differ, and exactly one copy of each reaches any build:

    source-lattice/{crossover,epix416,epix454}/Lattice.mc   the screen
    source-hands/{physical,drawn}/HandStyle.mc              what the hands are

    screen  COLS  RADIUS  HUB  dots   devices
    390       38     190   21  1112   instinctcrossoveramoled, epix2pro42mm
    416       40     203   22  1272   epix2, epix2pro47mm
    454       42     210   23  1380   epix2pro51mm

**`Lattice`'s constants stay `const` on both sides of the seam.** `DotGrid` re-declares them
(`const RADIUS as Number = Lattice.RADIUS;`) rather than reading through, so everything
downstream — ring bounds, marker windows, sub-band edges, the dot count — still folds at
compile time and the render loop keeps its rule. The `as Number` is not decoration: strict
typecheck loses the type across a module boundary and the build fails with *Member is
untyped*.

`PITCH` and `DOT` never move. `Drift`'s −2/+3 offsets are exactly `DOT` apart and consume
exactly the slack a 10px pitch leaves, so `PITCH` must stay `2 · DOT` and `DotGrid.ARMS`'s
half-lengths are tuned to `DOT` 5. Holding both fixed is also what makes **the luminance
budget scale-invariant**: dot density is `1/PITCH²` whatever the radius and each dot lights
`2·DOT−1`, so the all-lit fraction is 8.8% at 390 and 9.0% at 454. Every theme keeps its
measured figure on every watch, and `frameLuminance()` needs no change because it already
divides by the *lattice's* own `π·RADIUS²`.

`COLS` is the largest even count whose outermost dot survives the drift inside `SCREEN/2 − 1`.
`RADIUS` is the lattice's extent plus `DOT` — the relation the Crossover has — **except at
416, which takes 203 rather than 200**: past the extent `RADIUS` only clips the corners, but
it still sets the ring thickness, and at 200 the rings lose a pixel each and ring 1's
thinnest rain sub-band drops from 6 dots to 5, failing
`blockRingsResolveTwelveHoursInThreeBands`. That bar is scraped at 416 either way,
so a fourth screen size should measure it rather than assume it.

### The 454 lattice is smaller than the screen allows, and the watchdog is why

A native 454 fill wants `COLS 44` — 1512 dots, a 12px unlit rim matching the Crossover's own
10px. **It trips the watchdog with the hands on and will not load.** Bisected on the
simulator, hands on: 1388 dots runs, 1444 does not. 1380 is what ships, at a 22px rim.

The dots alone are not the problem — 1544 renders fine with the hands off. It is the hand
test on top of them, and the ceiling is genuinely close: the Crossover at 1112 is one
dot-count bump from its own cliff.

If this is ever revisited, the lever is `PITCH`, and `PITCH` drags `DOT`, `DotGrid.ARMS`,
`Drift`'s offsets and the whole Python mirror with it. That is a phase, not an edit.

### The hands are dots, and the bar test cannot be afforded per dot

`HandBacking.handAt()` answers *which* hand covers a dot — `NONE`, `HOUR` or `MINUTE` — and
the renderer indexes a three-slot colour table from `HandStyle.coloursFor()`. The Crossover
points both slots at its one backing colour, so its picture is unchanged; the Epix gives the
hour and minute the Crossover's own white and `0x808080`. **Minute is tested first**, so it
wins where they cross, which is the physical stack.

That is the whole mechanism. There is no polygon and **not one line of `FrameGate` changed**:
the minute already sits in the field print whenever the hands are on, so hand motion was
already a whole-field invalidation — one clear-and-redraw a minute. A drawn *polygon* hand
would need erase-and-restore of two corridors across all four rings, in both buffers, every
frame. It would also cost 5.03% of screen at 390 against a worst-theme field of 5.73%, over
the 10% cliff on its own; dot hands measure **+0.05 to +0.16 points**, because they recolour
dots already lit rather than adding lit area.

**The bar test is gated by an angular window, and that gate is not optional.** Eight float
multiplies on every dot tripped the watchdog outright at 1544 dots — the face refused to
load — and inlining the call, the move this codebase reaches for first, did not save it. So
`DotGrid.handHalf[ring]` carries the widest angle a hand can reach from that ring's inner
edge, `asin(HALF_WIDTH / inner)` in turns, and the loop tests it with the same two
comparisons the fill already makes. The bar runs on the few percent inside. Two shortcuts
fall out and both matter:

- the counterweight makes the **innermost** ring reachable in both directions, so it takes
  `0.5` — which `StatMap.windowAround` already turns into the whole turn — rather than
  pretending one window describes it;
- the hour hand does not reach ring 0's inner edge at **any** screen size, so the ring
  holding 40% of the dots tests one hand rather than two.

> **The window must be a superset of the bar, and it is not by construction.**
> `positionOf` is `Angle`'s polynomial approximation while the bar test is exact integer
> geometry, so a window sized to the true half-angle clips dots the hand really covers —
> measured at 0.00027 of a turn on ring 1, which draws as a hand cut off along its length and
> reads as a rendering quirk rather than a bound that is wrong. `handWindows()` opens the
> window by `Angle.MAX_TURN_ERROR`, and `theGatedHandTestAgreesWithHandBacking` is what
> caught it — on its first run.

**Where the hands are the face's, they survive always-on.** That is the one Crossover
decision the Epix inverts: there, backing is suppressed in low power to save light and the
brass keeps telling the time; here it is the only thing on the glass that does.
`HandStyle.ALWAYS_ON` is the switch and
`handsSurviveAlwaysOnExactlyWhenTheFaceDrawsThem` ties it to `DRAWN`.

### Touch-and-hold peeks behind drawn hands

The live watch face cannot intercept Epix button keys; those remain system controls.
`WatchFaceDelegate.onPress()` is different: Garmin defines it as touch-and-hold and supports
it on the Epix 2 family. `CrossoverDelegate` uses that event to toggle `CrossoverView`'s
transient peek. A peek removes drawn hands without changing `handBacking`, and `onEnterSleep`
restores them so always-on never loses the time. Physical-hand builds return false and leave
the gesture to the system.

The date is also a peek detail on drawn-hand watches. Hands + date + a busy ring
crossed the 416/454 watchdog after the two branches merged; each feature alone was safe.
`showsDate()` therefore defers the date while Epix hands are visible and reveals it when a
peek or Hands: Off makes the field unobstructed — a peek draws the outline in, as a wake
does. Crossover keeps the date normally because its hardware hands cost the renderer
nothing.

### Per-device resources go in one shared folder, not four

`resources-drawn-hands/` carries what the four hands-drawn watches override — `handBacking`
defaulting to **on** rather than off, the labels that would otherwise describe brass hands,
and a 60x60 launcher icon against the Crossover's 38x38 — and `monkey.jungle` appends it to
each of their `resourcePath`s.

It cannot be a qualified folder. `resources-<device>` would need four copies, and the family
qualifier is worse: `epix2pro42mm` is `round-390x390`, which is the **Crossover's** family
too, so a family folder would reach the one watch these overrides are wrong for.

The on-device menu needs no change for the labels — `SettingsMenu` already goes through
`Rez.Strings.*`. `simctl.settings` does not follow the override, though: it reads the base
`resources/strings/strings.xml`, so a label it prints for an Epix build is the Crossover's.

## Work happens in a worktree, never on main

The face has a working baseline now, so the repo root is a place to build, test and
sideload *from* — not a place to edit. **Every change starts in its own worktree under
`.claude/worktrees/`, on its own branch, and merges back to `main` only once it is
verified.** `/feature` does the whole cycle; `git worktree add .claude/worktrees/<name> -b
<name>` by hand is the same thing.

Two reasons this is now the rule rather than a suggestion:

- several agents work this repo at once, and a shared checkout means one session's
  half-finished edit is another's mysterious build failure — the isolation is what makes the
  parallel sessions below safe;
- `main` stays shippable. A worktree that turns out wrong is deleted, not unpicked.

The exceptions are the files that are shared by design — `Makefile`, `monkey.jungle`,
`CLAUDE.md` — where a fix is meant to land under every session at once (see the end of the
next section), and one-line hotfixes to a broken `main`. Everything else, including
"just a quick change", gets a worktree.

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

Taking turns is now avoidable: a session can run **its own** simulator instance instead of
queueing for the shared one — see *The simulator can be driven from an MCP server* below.
The lock still governs the shared simulator, which is what plain `make sim` and `make test`
use, so both worlds coexist.

If a run does die, `make test` now says so rather than blaming the tests: no `Ran N tests`
line means contention, and it names whatever is still attached. **Re-run before believing a
bare failure.**

**The watch is a singleton too.** `make install` / `make push` claim the USB interface, and
only one process may hold it. Nothing serialises that yet — coordinate by hand.

Editing `Makefile`, `monkey.jungle` or `CLAUDE.md` changes them under every session
immediately, worktrees included. That is usually what you want for a fix like the ones above,
but say so rather than letting another agent discover it mid-run.

## The simulator can be driven from an MCP server

`tools/sim_mcp.py` exposes the simulator as typed tools — `sim_status`, `sim_screenshot`,
`sim_settings_get/set/reset`, `sim_load`, `sim_release`, `sim_test` — registered project-wide
in `.mcp.json`. The logic lives in `tools/simctl/`, and every module is also a CLI, which is
how it is tested without an MCP client:

```sh
PYTHONPATH=tools python3 -m simctl.settings get          # what is actually persisted
PYTHONPATH=tools python3 -m simctl.settings set ring1=2  # no GUI, no Reset All App Data
PYTHONPATH=tools python3 -m simctl.window shot face.png --crop face
PYTHONPATH=tools python3 -m simctl.window list           # simulator windows, by instance
```

**Each MCP session gets one simulator, reused across its calls and devices.** The singleton
is a habit, not a constraint: `TMPDIR` moves the simulated device filesystem, `HOME` moves
the `Sim-$USER` file that refuses a second instance, and `SHELL_SERVER_PORT` moves the
control channel. `simctl/instance.py` sets all three, symlinking `~/.Garmin/ConnectIQ` back
so devices and the signing key stay shared. Omit `instance` for normal work, including a
device matrix: loading a new device into the default replaces the previous one. Only name
an instance when two simulator windows genuinely need to coexist.

`sim_release` stops both the sideload and a private simulator; it leaves the machine's
shared simulator running and releases only that lock. The MCP server also releases every
private instance at shutdown. Each instance carries an advisory lease, so after an abrupt
server death the next server can prove the lease is abandoned and reap it without matching
or killing another agent's process.

> **The MCP server drives the checkout *it* runs from, not yours.** `.mcp.json` is registered
> at the repo root, so `simctl.paths.repo_root()` — which resolves relative to its own file —
> is the **root** checkout for every session, worktrees included. `sim_load` therefore builds
> and sideloads main's face, and `sim_settings_set` validates against main's
> `bin/<App>-settings.json`, so a new setting in a worktree is refused as out of range with a
> message listing the old values. It looks exactly like a broken settings.xml. Run the CLI
> from inside the worktree instead — `PYTHONPATH=tools python3 -m simctl.settings ...` picks
> up that checkout's `tools/`, and so its `bin/`.

Pass `instance="shared"` to drive the machine's normal simulator instead. That path still
takes `tools/sim_lock.sh`, so it queues properly with plain `make sim` and `make test` in
sessions that never use the server.

> **`monkeydo` cannot be told which simulator to talk to.** `ShellUtils.findSimulatorPort`
> hardcodes a scan of ports 1234-1238 and takes the first that answers, and the class
> contains no `getenv` at all. `tools/simctl/shell_pinned.sh` stands in for the SDK's
> `shell` binary — monkeydo passes its path with `-s` — and rewrites the transport
> arguments to one port. Isolated instances also sit above 13000, outside that scan, so an
> unaware `make sim` in another worktree can never find one by accident.

Isolated runs reuse the real Makefile through command-line overrides, so there is nothing
to keep in step: `make test SIM_LOCK=true MONKEYDO=tools/simctl/monkeydo_pinned.sh`, plus
`SDK=` and `KEY=` because `connect-iq-sdk-manager` keeps its licence agreement outside
`~/.Garmin` and reports *agreement is not accepted* under a sandboxed `HOME`.

### Settings are a real file, not just a menu

Persisted properties live at
`$(getconf DARWIN_USER_TEMP_DIR)com.garmin.connectiq/GARMIN/APPS/SETTINGS/CROSSOVERFACE.SET`
— per-user, per-boot, so resolve it, never hard-code it. The format is decoded in
`simctl/setfile.py` (magic `abcdabcd`, a key table, `da7ada7a`, then 10-byte entries) and
`tools/testdata/CROSSOVERFACE.SET` pins it with a **byte-exact** round-trip test.

Two traps the tools handle and a human editing by hand would not:

- **Stop the app before writing.** A running app flushes its in-memory properties over the
  file when it terminates, silently reverting the write. `sim_settings_set` kills the
  sideload first.
- **The face and the test build share one file.** Both carry manifest id `d711a1ab-…`, so
  any `make test` run overwrites settings. Set settings *after* testing, never before.

`bin/<App>-settings.json`, which `monkeyc` generates, is used to validate values and resolve
labels — so a new setting needs no change here. It is build output, so `sim_settings_set`
fails with *run `make build` first* rather than writing something unvalidated.

### A screenshot is the only way to see the face, and its luminance lies

The SDK has **no** screenshot command and **no** input injection — confirmed absent from the
simulator binary and its shell command table. So capture goes through macOS:
`simctl/window.py` finds the window with CoreGraphics via `ctypes` (no pyobjc, so stock
`python3` runs it), matched by owning pid so each instance screenshots its own, and shells
out to `screencapture -l`, which works on an off-screen window without stealing focus.

**The reported luminance is not the 10% budget figure.** A capture includes the simulator's
drawing of the two *physical* analogue hands, which emit no light on the real watch: measured
11.17% as captured against 5.43% with the neutral-grey pixels removed. `MatrixTest`
and `tools/mockup.py` remain the authorities — both measure the dot field before hands. That
caveat is the Crossover's; an Epix capture has no hands drawn over it, but the crop below is
approximate there, so the in-suite figure is still the one to quote.

**Locating the face in a capture is per-device, and both halves of it were wrong for
anything but the Crossover.** The artwork is named by the profile — only the Crossover calls
it `device.png`, the Epix names the file after the device — and it is *not* drawn to the
window width: that window pads the watch with white and puts a taller status strip under it,
so a width-derived scale came out 2.0 against a real 1.84 and cropped a ring of bezel into
what was supposed to be the display. `locate_device()` now measures the scale off the white
page around the artwork, because bezel probes cannot fit it — the bezel is mostly black, so
black matches black at any scale. **The Epix crop still lands a percent or two out**; it is
good enough to see the face by and not good enough to measure.

> **An all-black capture means the Mac display slept**, which stops the Monkey C VM and
> makes a healthy face look like a hung test run. Worse, window capture then fails outright
> with *could not create image from window*, which reads as a missing Screen Recording
> permission. `window.display_is_asleep()` tests for it and `capture()` retries once after
> `caffeinate -u -t 5`. A locked screen cannot be woken from the shell.

### Command gotchas

- **There is no lint or typecheck step.** `monkey.jungle` sets `project.typecheck = strict` and
  the Makefile passes `-w`, so a clean `make build` *is* the type check. Don't go looking for one.
- **But `make build` does not type-check `MatrixTest.mc`.** That file is `(:test)` and only
  compiles under `-t`, so a green `make build` says nothing about it. Worse, the failure
  *looks like contention*: `make test` compiles before it runs, a compile error means no
  `Ran N tests` line, and the target's own diagnosis reports "the simulator died" — the one
  thing you have been told to re-run rather than believe. Two ways to tell them apart: read the
  raw output for `ERROR: instinctcrossoveramoled:`, or build the test `.prg` on its own first —
  `"${SDK}bin/monkeyc" -f monkey.jungle -o bin/CrossoverFace-test.prg -y "$KEY" -d
  instinctcrossoveramoled -w -t`. Do that after editing tests, before blaming the simulator.
- **`monkeydo` exits non-zero even when every test passes**, which is why `make test` greps for
  `^PASSED` and ignores the exit code. Never judge a raw `monkeydo` run by its status code — read
  the summary line.
- **A killed simulator looks like a test failure.** If `make test` prints nothing but
  `TESTS FAILED`, the simulator died mid-run. The target now diagnoses this itself — no
  `Ran N tests` line means contention, not a bug — but re-run before believing it either way.
- **The watch must be in MTP mode and OpenMTP must not be running.** Only one process may
  claim the USB interface; `make push` quits OpenMTP for you. USB product IDs are
  model-specific — measured `0x5246` on the Crossover and `0x50DA` on an Epix Pro 51 mm —
  so `make install` asks the MTP engine whether the device is usable instead of matching
  one ID. Current firmware is in MTP by default and no longer asks *Use MTP?* on
  connection. The first probe after plugging in can fail on its own, so `make install`
  retries once; run `python3 tools/mtp_push.py --info` to see the real error.
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

`DotGrid` caches parallel arrays (`xs`, `ys`, `positionOf`, `armOf`, and the byte-per-dot
`blockAt` that only block rings read) built once per rebuild; `MatrixRenderer` is a flat indexed walk. There is no `ringOf`: dots are stored grouped
by ring, so `ringStart` already says which ring an index belongs to. The single deliberate exception is
`StatMap.isLit()`, called per dot (~6ms/frame) so the lit test has one definition shared with the
tests.

Caching the field to a `BufferedBitmap` is not worth doing, but **not for the reason this
note used to give**. It said 390×390 at 16bpp is ~304KB against a 128KB budget. Measured in
Phase 4: a full-screen buffer allocates fine, and the app heap moves by **616 bytes**,
because `Graphics.createBufferedBitmap` allocates from the *graphics pool*, which the SDK
documents as separate from the application heap since API 4.0. Every rung of the ladder —
16bpp, 8bpp, 8bpp with a palette, 4bpp — allocated. Memory was never the objection.

What rules it out is the frame cost. Presenting a full-screen buffer measured ~20ms, against
36ms for the whole single-ring redraw it would replace — so a mirror trades most of a partial
frame for a blit and gains a 304KB dependency. Populating it measured far worse still,
though that figure is a simulator artifact rather than a cost model. See ROADMAP Phase 4.

Two API facts if this is ever revisited: the pool **purges a buffer whose `BufferedBitmap`
object you do not hold** — the reference alone is not enough, and re-`get()`ing per frame
cost ~5200ms a frame — and `dc.setAntiAlias(false)` **throws** on a paletted buffer
(*"Anti aliased primitives cannot be drawn to a paletted buffer"*) while `dc has
:setAntiAlias` still answers `true`, so the guard in `MatrixRenderer` does not catch it.

**Most frames are not drawn, and most of the rest draw one ring.** `FrameGate` is what
decides, and it is the largest lever the face has — bigger than anything left inside the
loop. It fingerprints each frame in two parts: a *field* print (drift, hands) whose change
clears the screen and redraws everything, and a *ring* print per ring (span, mark, over
flag) whose change redraws only that ring. Awake and still, nothing is drawn at all.

`MatrixRenderer.draw` therefore takes a dirty set and a `clears` flag, and a clean ring is
not walked. **A dirty ring is not fully redrawn either**: it is walked, and only the dots
whose lit-ness actually changed are drawn — measured at 7ms against 24ms, 20 dots against
436, on a seconds ring. Three rules make partial redraw safe and none is optional:

- **every change is drawn `HOLD` (2) consecutive draws.** Not drawing is safe whatever the
  device does with its buffers; drawing *part* of a frame is only safe if the Dc handed to
  `onUpdate` holds what was last presented, and on a double-buffered device it holds the
  frame from two draws ago. Repeating into two draws covers both;
- **`FrameGate.sinceClear` forces a full clear every `MAX_SKIPS` frames.** A partial redraw
  repairs nothing outside the ring it draws, so without this a seconds ring — which never
  skips — would never clear, and a notification drawn over the face would stay there. It
  counts skipped frames too, which is what preserves the old cap's guarantee exactly.
  That repair is **one** frame, not `HOLD` of them, and the asymmetry is deliberate: a
  clear plus four rings defines the whole buffer by itself, so repeating it buys nothing.
  Holding it was measured at default rings — where the repair is nearly every draw there
  is — and cost the skip rate 82% → 68% for no visible difference.

- **a delta is measured against the *two* spans a ring was last drawn with**, and may
  differ by span alone. Two, because the buffer this draw lands in was written two draws
  ago, so a dot is repainted when it differs from *either* remembered span — that set is
  correct for whichever buffer it is, with nothing to reason about. And span alone, because
  both colours, the over flag, the ramp and the backing repaint the ring wholesale; they are
  compared as **values**, not inferred from the settings that move them, so a cause nobody
  anticipated cannot slip through. A ring whose colours changed is repainted in full
  **twice**, since both buffers hold the old tiers. `theDeltaCoversBothBuffersNotJustTheLastDraw`
  is the guard that matters here: a delta taken against the last draw alone looks right on
  screen and leaves every other frame a step behind.

**An over-goal ring opts out of the delta too**, and for two reasons at once rather than the
block ring's one: its mark is a *run* of `DotGrid.MARK_DOTS` cells rather than a single one,
so the force set the delta carries would be six comparisons per dot instead of two; and its
lapped dots are solid blocks, which a nine-pixel cross cannot rub out. Both are in
`overs[ring]` in the eligibility key, in *both* places that key is compared. A goal moves
once a minute, so the gate had already skipped nearly every frame there was anything to save
on. `anOverRingOptsOutOfTheDelta` is the guard.

A mark is a solid block and a dot is a cross, so repainting a ring covers only 9 of the 25
pixels a mark occupies. `MatrixRenderer` blacks the cell before repainting —
unconditionally, since the ring is being repainted anyway and that needs no reasoning about
which frame a move landed on. Under a delta redraw the erase needs one more thing: the cell it blacks is the
whole of that dot, and a delta will not repaint it because its tier did not change — so the
rubbed-out cells are forced back into the paint set, or a moved mark leaves a hole exactly
where the reading was. It keeps **two** slots, `drawnMark` and `previousMark`, and
blacks both: with one, a mark moving P→Q rubs out P on the first held draw and Q on the
second, so the buffer the second draw lands in keeps P's sixteen stray pixels under a
nine-pixel cross. That is the one place where `HOLD` alone is not enough.

### Measuring a frame

`Diagnostics` keeps two averages, and they answer different questions: the **drawn** cost is
what the watchdog is judged against, the **idle** cost is what a frame pays to decide it has
nothing to do. Never fold them together. Set `Diagnostics.TRACE = true` to have the summary
printed every ten frames — that is the only way to read it outside the on-device menu, since
the simulator has no input injection to reach that menu with.

**For the watchdog itself, measure headroom, not milliseconds.** A timing says how slow a
frame was on this machine today; whether it trips is a different question, and with other
simulators loading the Mac the timings stopped meaning anything at all (multi-second
"averages"). The probe that settled three block rings: a temporary build that forces a full
clear and forgets the data caches every frame — every frame a worst-case first frame — then
runs an empty `for` loop of `PAD` iterations after the draw, printing `PAD` and growing it by
100 a frame. The `PAD` printed when the watchdog trips is that configuration's headroom.
Within a session it repeats to about ±200; across sessions it drifts, so interleave the A and
B legs. Compile the ring set into the probe rather than writing settings — a fresh
instance's first push resets `CROSSOVERFACE.SET` to the defaults.

**Measure with an A/B out of one binary, never against a figure from another day.** This
machine ran ~2.4x the frame times of the ones in `2ec08e3`, and a second simulator starting
up mid-session moved a "before" by 9ms on its own — enough to invent a regression that was
not there. The A/B that produced the figures below put a temporary `const` in `plan()` that
reproduced the old whole-frame behaviour, so both legs came from one build under one load.

    rings                    whole-frame gate   per-ring gate
    seconds + temperature    89ms / 115 worst   31ms / 97 worst    1% -> 0% skipped
    defaults                 85ms / 118 worst   70ms / 94 worst    82% -> 81% skipped

Read the defaults row as the regression check it is. The skip rate is unchanged, because
with four slow sources the whole-frame gate already skipped ~82% of frames and there was
nothing there to win; the drawn frames got cheaper only because some of them are now a
single ring rather than all four. **If you add per-dot work or raise the dot count,
re-measure both rows.**

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
dot, **22,240 bytes at 1112 dots**, five bytes a slot, plus `blockAt`, a `ByteArray` at one
byte a dot. `theDotCacheFitsItsShareOfMemory` measures it and fails if another full per-dot
array appears. That test has to drop the arrays'
references before sampling: a rebuild in place frees each old array as the new one is assigned,
so measuring across `invalidate()` alone reports a delta of nothing and passes vacuously.

`make install` ships the debug build on purpose — symbolicated `CIQ_LOG` traces are worth more
than the flash on a face with a watchdog history. See the comment on `install:`.

### Config.reload() ordering is load-bearing

`StatMap.load()` → `Palette.build()` → `DotGrid.build()`. Which theme the rings carry is
itself a setting, so a load without a rebuild draws last session's colours. Anything that
changes a setting must go through `Config.reload()`, not a partial refresh.

An older comment here claimed the hues came from each ring's *source* assignment. They never
did — `Palette.build()` reads `StatMap.RINGS`, the count, and has never read `StatMap.rings`.
The ordering is real; that reason for it was not. Nothing settable moves the
lattice any more, so `DotGrid.invalidate()` is now a safety net rather than a requirement —
but the rebuild it schedules must still land in `onLayout`, never `onStart`.

### Block sources do not report spans

Rain, UV and temperature forecasts plus Body Battery history fill the shape the face calls
**blocks**.
The ring's 360° is twelve 30° hour slots, a 22.5° block **centred in each** leaving a
countable gutter that straddles the hour mark, and how much of each block is filled is the
reading. Forecasts proceed clockwise; Body Battery's current hour is live and its eleven
completed-hour averages read counter-clockwise. Twelve disjoint blocks with a radial axis
is not something two floats can say, so each block source reports `Source.EMPTY` as its span
and its real payload travels beside it: `Source.fillBlocks()` → `StatMap.blocks()` → the
view → both the print and the renderer. The same move a marker makes, and for the same reason.

**A block holds a level from 0 to `HourBands.LEVELS` (15), not a sub-band index.** The lattice
caps the radial axis at three sub-bands and there is no arguing with it, but a block is also
8–13 dots *wide*, and that axis was unused while every lit band was drawn full width. So level
`L` fills `L * BANDS / LEVELS` bands: the whole part is that many full-width sub-bands, the
remainder is the angular half-width of the next band out, centred in the block. Sixteen
readings an hour rather than four — a 10% hour is a two-dot pip on its hour mark rather than
the nothing the old 25/50/75 scale drew for it.

Consequences worth knowing before touching it:

- **The scale is linear in area and its top is the source's 1.0**, not "75% or more". Rain
  and Body Battery normalise 100% to full; UV normalises index 10 to full. One whole
  sub-band means a third. `HourBands.fullBandsFor()` /
  `partialHalfFor()` are the only place that curve lives.
- **The block is centred in its slot, and it was not always.** It used to sit at the wedge's
  *leading* edge — starting exactly on hour mark `H`, with the whole gutter bunched up before
  mark `H+1`. That put every block 3.75° anticlockwise of its slot's centre, about 12px of arc
  on the outer ring: invisible to every test the face had, and obvious on the wrist against the
  printed dial. `HourBands.LEAD` is the half-gutter that fixes it, and
  `everyBlockIsCentredInItsHourSlot` is what holds it — written against the *symmetry* of the
  lit arc, so `HOUR_BLOCK_DEGREES` stays a free choice. `BLOCK_CENTRE` is then exactly 0.5 for
  any block width, because `LEAD` is by definition half of what `FILL` leaves over.
- **Centring costs the bottom rung its evenness**, and a floor does not buy it back. It puts
  blocks 1, 4, 7 and 10 with their centres on the lattice's 45° diagonals, where dots sit
  further apart, so level 1 draws 1 dot at those four hours and 3 at the rest. A minimum window
  of a lattice pitch or less changes nothing; 1.4 pitches evens level 1 to 3–4 dots, which is
  exactly what level 2 draws — collapsing two rungs into one. Every rung above 1 came out
  *more* even than before, and ring 1's full block is now a flat 21 dots across all twelve.
- **Level `LEVELS` is exactly the old top tier**, so the widened scale can draw nothing that
  was not already drawable and **no luminance bound needed re-measuring**.
  `eachSubBandLightsItsShareOfTheRing` asserts that equality rather than assuming it.
- **The outer two rings have no minimum window, and ring 2 has one — both measured.** The
  worry is that a level-1 window, a fifth of one band, falls between two dots and the bottom
  of the scale draws nothing. On rings 0 and 1 it does not: the worst block at level 1 holds
  two dots and one, and every level is monotonic in every block. On ring 2 it did — eight
  (block, level) pairs blank on 416 and 454, one on 390 — so `HourBands.WINDOW_FLOOR` gives
  ring 2 alone a floor of 0.12 of a wedge, applied through `partialHalfOn(level, ring)`. That
  lights every pair on all three screens while leaving levels 1 and 2 exactly as distinct as
  they were (equal in 4 of 12 blocks either way); 0.15 merges them in all twelve. It only
  raises levels 1, 6 and 11, and it is computed once per block per frame, not per dot.
  `everyNonZeroLevelLightsAtLeastOneDot` and `aLevelIsMonotonicInDotsLit` hold all three
  offered rings to it. `tools/mockup.py` mirrors the floor.
- **A block ring costs about 2.7ms more per drawn frame** than the whole-band fill did (87ms
  against 85ms on ring 0's 436 dots, worst case, A/B'd out of one binary). The span loop is
  byte-for-byte unchanged, so no other ring moved.
- **Which block a dot is in is cached, not computed** — `DotGrid.blockAt`, a byte a dot,
  holding the block or `HourBands.GUTTER`. Working it out per dot (a multiply, `toNumber()`
  and two gutter comparisons) is what put three block rings past the Crossover's watchdog;
  read from the cache it gave back about 600 `PAD` iterations per block ring. The renderer
  inlines `HourBands.litInBlock()`, which only computes how far into its block a dot sits
  inside the partial band's radius. `theCachedBlockCodeLightsWhatLitAtDoes` pins it to
  `litAt()` on every dot at every level; `theBlockCacheMatchesItsDefinition` pins the cache.

Five things about the channel are load-bearing:

- **The hour-hand anchoring is free.** The hand at local hour `H` points at clock position
  `H mod 12`, so the forecast `N` hours out belongs at `(H + N) mod 12` — which *is* that
  forecast hour's own hour-of-day, mod 12. `HourlyWeatherData` buckets straight into that
  position. Body Battery samples use their own past local hour, so walking back from H lands
  at H-1, H-2 and proceeds counter-clockwise. **Nothing rotates anywhere.** Code that turns
  a table once an hour was written the hard way.
- **All three packed words must be in the ring print.** A block ring's span is `EMPTY` on
  every frame it draws and it carries no mark and no overflow, so without them nothing about
  that ring ever changes and the gate never marks it dirty. `PER_RING` is 7 for this. Three
  words because a level is four bits: twelve blocks is 48 bits, and neither a Float nor a
  Number round-trips that, so the levels take two words of six blocks each (`0xFFFFFF`) beside
  the twelve known bits (`0xFFF`) — all three inside a Float's exact integer range.
- **It opts out of the delta redraw**, via `lastBlocks` in the eligibility key — in *both*
  places that key is compared, the delta test and the `stableFor` update. The palette is
  keyed by ring rather than by source, so switching a ring in or out of the forecast moves
  nothing else in the key. The direction that rots is *leaving* it: the buffers hold blocks
  and gutters while the remembered spans describe `EMPTY`.
- **`StatMap.noBlocks()` reports every block known and *empty*, not all zeroes.** Zero `known`
  means every hour is unknown, which draws the dim tier right round the ring — data, in the
  held-back mode whose entire purpose is to carry none.
- **Nothing outside `Source.usesBlocks()` names the kind.** The renderer, the loader and the
  picker all have to ask which *shape* a ring draws; individual block kinds are cases in
  `Source.fillBlocks()` and nothing else. `HourBands` owns the packing
  (`raise`/`setLevel`/`levelAt`) and the scale (`levelFromFraction`), and knows nothing about
  rain, UV or Body Battery.

Three sub-bands rather than four was measured, not chosen: four splits a 42px ring into
10.5px bands that beat against the 10px lattice pitch, and ring 1 comes out 7.0/5.7/9.0/6.7
dots per block against three-way's 8.3/9.0/11.0. `DotGrid.bandEdges()` therefore uses the
**integer** thickness `ringBounds()` uses, never `markerWidths()`'s 42.25 — the float one puts
ring 1's top edge inside ring 1's own outermost dots.

They are offered on the **outer three rings** (`Source.BLOCKS_TOP_RING = 2`), enforced in three
places that must agree: `StatMap.load()` maps them to Off on the innermost, the on-device
picker walks `Source.offeredFor(ring)`, and `settings.xml` lists them in the `ring1`–`ring3`
blocks. The justification is a claim about the lattice and is asserted as one —
`blockRingsResolveTwelveHoursInThreeBands` measures the worst (block, sub-band) at 8–9, 6–7,
3–4 and 1–2 dots on rings 0–3 across the screens, against `MIN_BAND_DOTS = 3`. Ring 2 is
coarse — a reading there is three or four dots a sub-band — and was let in as the wearer's
trade rather than kept out on a threshold, once its window floor (above) made every rung
visible. The innermost ring stays out: eight (block, level) pairs light nothing there, which
no floor fixes without merging rungs.

**Three block rings are what the watchdog budget is sized against.** Measured with the
headroom probe (see *Measuring a frame*), Crossover, hands on, every frame a worst-case first
frame: default rings ~3600, two block rings ~2300, three ~1300–1400 with temperature and
**~200–700 with Body Battery** — thin, and the simulator holds no Body Battery *history*, so
on a wrist the hourly history read adds cost the simulator never shows. Every combination of
three held for 75s of forced worst-case frames. **The Epix screens do not fit two**: the 416
with drawn hands holds one block ring (on any offered ring) and trips with two, and the 454
trips on default rings — both on `main` before ring 3 was offered. Re-run the probe whenever
per-dot or first-frame work grows.

### Past the goal, a lapped dot changes shape rather than colour

Steps and intensity minutes can be beaten, and past 100% the overflow runs a second lap:
the span is re-pointed at the lap and the ring's two tiers are swapped, so unfilled means
"goal met" and filled means "gone past it".

**The tier swap alone does not read, and that was measured.** Band 0.77 against over 0.84 on
the moss ring, on five-pixel crosses — rendered side by side, 100%, 134% and 250% could not
be told apart. Tinting harder is not available: `OVER_TINT` is boxed in between the band and
`MARKER_TINT`, which `everyThemeKeepsTheTierOrder` pins. So a **lapped dot is drawn as a
solid `MatrixRenderer.LAP_BLOCK` square** rather than as a cross. Same law as the temperature
mark and the date watermark: on a field of thin crosses, only a change of density reads.

Five things follow and none is obvious:

- **`LAP_BLOCK` is 4, not `DotGrid.DOT`.** All three solid sizes read identically at 1:1, so
  the size answers to luminance alone: one full lap on ring 0 costs 5.43% as crosses, 7.27% at
  4x4, 9.65% at 5x5. 3x3 is nine pixels — free — and is the one that fails, because a smaller
  footprint reads *dimmer*, which is backwards. The price of 4 over 5 is that the block does
  not cover the cross it replaces: the right and bottom arm tips, two pixels, survive a
  *growing* lap until `FrameGate.sinceClear` blacks the screen a few seconds later.
- **An over ring walks its own loop**, beside the block ring's. `lit && overs[ring]` in the
  span loop is a test paid on all ~1100 dots to serve a ring that usually is not over. Split,
  the span loop is byte-for-byte unchanged, so **no frame without a lap in it moved at all** —
  which is what discharges the re-measure-both-rows rule for this change.
- **The hands outrank the lap's shape as well as its colour.** A backed dot is an ordinary
  cross in the backing colour, in every loop; a block there makes the hands read denser
  wherever a lap runs under them. This was a real bug, caught by
  `aLappedDotIsFilledAndAnUnlappedDotIsNot`.
- **A lapped dot swallows the strike it would have carried**, and the watermark cursor
  advances with it. There is no numeral left to preserve under a 16-pixel block, so this is
  honest rather than a compromise — but the cursor must still land exactly at the end of the
  ring's slice, which `aLapSwallowsTheStrikesItCovers` is what holds.
- **The luminance figures are awake-only figures.** Every ring full with both goal sources
  past double is 10.3% of screen on the worst theme, and 10% is the threshold Garmin blanks an
  *always-on* face at — `StatMap.overs(false)` is all false, so always-on never reports a lap.
  `overGoalCostsLittleLuminance` walks every theme and states that explicitly rather than
  asserting a budget that does not govern. Note it needs its own `lapFrameLuminance()`: the
  ordinary `frameLuminance()` charges every dot nine pixels, which is why the shape change
  slipped past every luminance test in the file until that existed.

**The waterline is a radial tick, and it sits outside the lap.** Two decisions, both of which
look wrong until rendered:

- **One dot per band of radius**, in `DotGrid.markedDotsFor()`. Not everything inside the
  mark's window, which is a wedge — the window is a pitch of arc at the ring's *inner* edge,
  so it is two dots wide at the outer. And not one dot per lattice *row*, the obvious reading
  of "radial", which collapses to a single dot at three o'clock where the ring's radial
  direction runs *along* a row. A band of radius is orientation-free; that is the whole
  property. It comes out 3–5 dots on every ring, which is what the lattice gives rather than a
  choice.
- **Placed one pitch of arc *past* the lap's end**, in `StatMap.markers()`. Inside the lap it
  is solid against solid with only its colour left — the exact failure that made the lap solid.
  Outside it, it lands on plain crosses where a solid block is again unique. It still marks the
  boundary, from the outside. The `>= 1.0` suppression now tests the *offset* position, since
  that is what would wrap.

The temperature mark stays a single dot. `markedWide` is in the cache key because a ring
crossing its goal keeps the same position while changing how many cells it occupies, and
`markedAt` is flat, `MARK_DOTS` per ring, padded with -1 at the tail.

### Sunrise and sunset ride beside the temperature mark

`SOURCE_TEMP_SUN` is the temperature range plus two solid dots: sunrise (`0xFFE680`) on the
ring's **outer** edge, sunset (`0x4D8CFF`) on its **inner** edge — each mixed 70% toward its
ring's band (`Palette.sunOf`, `SUN_TINT`) so it sits in the theme — each at its time on the
twelve-hour dial. Opposite edges because 06:05 and 18:10 are the same position on that
dial. `Source.isTemperatureRange()` is the predicate for span, mark and ramp — never test
`SOURCE_TEMPERATURE` alone.

- **The current-temperature mark is soft now too**: `Palette.softMarkOf`, 85% band
  (`SOFT_MARK_TINT`). Only the over-goal waterline still uses `markerOf`/`MARKER_TINT`,
  because it must stand above the lap tint. Density, not brightness, is what makes a
  solid dot findable.
- **The times come from the Sunrise/Sunset complications**, which need the
  `ComplicationSubscriber` permission. `Weather.getSunrise()` needs a location, and the
  weather's `observationLocationPosition` is null without Positioning.
- **The sun channel is two floats a ring** (`Source.SUN_VALUES`), in the ring print, so
  `PER_RING` is 9. A moved sun dot costs its ring the delta for one frame instead of adding
  a per-dot test; an unmoved one is simply redrawn after the loop.
- **Placing a dot no longer walks the ring.** `DotGrid.nearDot()` searches the 5x5 cells
  round the anchor point and binary-searches the index; three walks (mark + two suns) on
  one frame tripped the 416 watchdog with hands drawn. `theQuickMarkSearchAgreesWithTheWalk`
  pins it to `markedDotNear()`, the definition.
- **`drawAt()`'s frame is at the stack's limit.** Inlining the sun placement overflowed the
  test runner's stack, which is why it lives in `placeSuns()`/`drawSuns()`. The deepest path
  is `drawAt()` → `ensureBuilt()` → `build()` → a helper, taken whenever a test leaves the
  lattice stale: a new local in either `drawAt()` or `build()` overflows it, and the failure
  shows up in whichever later test first draws, as *Stack Overflow Error* in `bandEdges()`.
  `fillBlockCodes()` is a function of its own and `Palette.markerOf`/`overOf` are not
  hoisted for that reason.

### Every other source reports a span, not a level

`Source.span()` returns `[start, end]`, both 0.0–1.0. Levels are just `[0.0, value]`. This is why
temperature — a genuine range — needs no special case anywhere downstream.

`end < start` is **legal**: the temperature scale (0–60°C, one degree per minute mark) wraps
rather than clamps, so a sub-zero range runs from e.g. :55 round past twelve to :03.
`StatMap.isLit()` handles the wrap. Don't "fix" it by clamping — that silently misreports a
−5→3°C day as 0→3°C, and `subZeroWrapsBackPastTwelve` guards it.

### tools/mockup.py mirrors the Monkey C by hand

The Python mockup duplicates the lattice constants, `THEME`, `WEAK_*`/`LIFT`, `ARMS`, the
ring mapping, the hand geometry and `handAt`'s minute-first order. It is not generated.
**Any change to geometry or palette must land in both**, and `MatrixTest.EXPECTED_DOTS` plus
the luminance tests pin the two implementations together so they cannot drift silently.

There is no jungle to pick a `Lattice` in a script, so `mockup.LATTICES` is one row per
`Lattice.mc` and `use_device()` rebinds the module's globals. `python3 tools/mockup.py
<outdir> <device>` renders any of the five; on a hands-drawn watch the hands appear *in* the
field rather than composited over it, and `composite()` skips the overlay because those
profiles carry no `analogHands`.

### Settings live in five places that must stay in step

Stored values are **list indices**, so `resources/properties.xml`, `resources/settings/settings.xml`,
`resources/strings/strings.xml`, the enums in `StatMap`/`Source`, and the label arrays in
`source/settings/SettingsMenu.mc` all have to agree. Twelve properties today: `theme`,
`handBacking`, `alwaysOnFill`, `dotRotation`, `showDate`, `dateOutline`, `ring1`–`ring4`,
`tempAheadLow`, `tempAheadHigh`. `dotRotation` stores three values and offers two: the third, Upright +
date, is **retired** — `StatMap.load()` reads it as Upright, and `showDate`'s default of On
keeps that wearer's date. Never give 2 a new meaning.

**The two temperature-ahead ends are the exception: they store degrees Celsius, not an
index.** −20 to 50, empty block at `tempAheadLow`, full at `tempAheadHigh`.
`StatMap.loadTempAheadScale()` swaps an inverted pair and widens an equal one, because the
phone accepts each end alone; `HourlyWeatherData` divides by the gap and relies on it.
The levels are bucketed against the scale when sampled, so `Config.reload()` calls
`HourlyWeatherData.forget()` — drop that and a scale change takes a minute to appear. The
on-watch entry is two rows *after* the four rings in `RingMenu`, so ring rows keep their
indices; each opens a 71-row `ChoiceMenu` focused on the value in use, measured at ~12.7KB
of heap while open (`theTemperaturePickerOpensOnTheValueInUse` logs it).

A `ChoiceMenu` is given how many values it offers as well as its labels. Adding a label
without moving that count leaves the new row unreachable with no other symptom, which is
what `rotationSettingIsClamped` now walks every value to catch.

**The indices are the same on every watch, deliberately.** `resources-drawn-hands/` overrides
only `handBacking`'s *default* and some labels; forking the schema per device would multiply
this rule by five for nothing, and a setting would stop meaning the same thing across them.

**A new source is appended after `SOURCE_OFF`, not before it.** That looks wrong and is the
only safe place: the stored value is an index, so inserting below Off renumbers Off and
everything under it on every watch already carrying a setting. `SOURCE_RAIN_HOURS = 9`,
`SOURCE_UV_HOURS = 10`, `SOURCE_BODY_BATTERY_HOURS = 11`, `SOURCE_TEMP_HOURS = 12` and
`SOURCE_TEMP_SUN = 13` sit above `SOURCE_OFF = 8` for
that reason, while `Source.OFFERED` — which decides picker *order* — groups each with its
related source. `sourceTablesCoverEveryKind` used to assert
`SOURCE_OFF == COUNT - 1`; that was always a claim about `OFFERED`'s order and only happened
to be expressible as an enum index while nothing had been added after Off, so it is now made
against `OFFERED` directly.

**A source is retired, never deleted.** Because the stored value is an index, removing an
enum entry does not remove a source — it renames every source above it, on every watch
already carrying a setting, with nothing to report that it happened. `SOURCE_RETIRED = 1`
was heart rate and holds its number for that reason. Three things follow and have to move
together: `Source.OFFERED` is what the picker walks, and it skips the gap;
`StatMap.load()` maps a stored retired value to `SOURCE_OFF`, so a ring left on it reads as
something the menu can name; and `ChoiceMenu` takes an explicit `values` array beside its
labels, because a picker with a gap can no longer use its own positions as values.
`retiringASourceLeavesEveryOtherIndexAlone` pins every index outright — if that test starts
failing, the field's settings are about to change meaning.

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

### A theme is four ring slots and three ramp stops

`Palette.THEMES` holds only shipping ring colours **flat**, indexed by the dense slot returned
from `StatMap.themeIndex()`, for the reason `DotGrid.ARMS` is flat: a const array of arrays is
further than Monkey C's `const` is meant to go, and nesting it resolves in the simulator and
comes back empty on the watch. `RAMP_STOPS` is flat for the same reason.

There are four shipping themes, outermost to innermost:

- Terrain: orchid `#E879F9`, moss `#B8D64B`, ice `#7FD4FF`, rust `#FF6B5B`.
- Activity: red `#FE4646`, green `#6DC54F`, blue `#1F8FFE`, gold `#E59A0A`.
- Beacon: cyan `#5CD9F0`, red `#FE4646`, indigo `#8E7BFF`, gold `#E59A0A`.
- Pulse: red `#FE4646`, teal `#2FD9C5`, orchid `#E879F9`, lime `#B8D64B`.

The temperature ramp names three **indices into the theme, not colours**: a ramp stop *is* a
ring colour, and writing the value a second time is how the two drift apart. Terrain runs ice
→ orchid → rust; Activity runs blue → gold → red; Beacon runs cyan → gold → red; and Pulse runs
teal → lime → red. Every theme has three explicit stops, so `Palette.build()` does no per-theme
branching while it constructs the ramp.

Persisted theme IDs are deliberately sparse. Terrain remains `0`, Activity remains `1`, and
IDs `2` through `6` are retired forever. Any watch still storing one of them falls back to
Terrain. Beacon uses `7`, Pulse uses `8`, and the next production theme must use `9`.
`StatMap.THEME_IDS` maps those sparse persisted IDs to dense Palette table slots. Never reuse a
retired ID or index a palette table directly by the persisted ID.

Adding a production theme means changing the colours and ramp stops, the persisted ID list,
the on-device label table, the resource string and phone-side settings entry, and the exact
theme tests together. `themeTablesCoverEveryTheme` holds all table/list lengths in step;
`everyThemeFitsTheAlwaysOnBudget` and `everyThemeKeepsTheTierOrder` walk every shipping ID.

Activity's colours are not invented: they are the accent colours the watch itself uses, read
off the peak-chroma pixel of the device's own `nwidget_*.png` and `D_list_select_*.png`
swatches, whose hues agree to a tenth of a degree across both sets. Gold is on ring 4 because
the innermost ring has by far the fewest dots, and it sits beside blue rather than either of
the closer hues.

`tools/mockup.py` keeps Arcade in a separate candidate-only table. It appears in
`10-candidates.png` in awake, always-on and temperature-range views, but has no persisted ID,
string or settings entry and therefore cannot reach a watch build.

### Dot rotation is a render choice, not a cached one

`StatMap.rotation` decides only whether `MatrixRenderer` indexes `DotGrid.armOf` per dot or
uses the one upright cross it hoists. Which way a cross *would* point is geometry, so it is
cached either way and toggling the setting needs no rebuild. Do not move this into
`DotGrid.build()`: it would cost a full ~1100-dot rebuild per toggle, and the next step from
there is making the ring mapping conditional again. `rotationDoesNotReachTheCache` is the
guard. Every orientation lights nine pixels, so neither setting moves the luminance.

### The date is the dots, joined

`showDate` (on by default) draws the day of the month as a faint **outline joining the
numeral's own dots**, centre to centre, at `DateGlyph.linePercent()` of the colour of the
dot each line leaves from — 50, 65 (default) or 80%, the `dateOutline` setting. The dots themselves are ordinary crosses. `DateGlyph` owns
the window, the font, the list of dots, the outline and its reveal order; nothing else
learns what a digit is.

**Awake only.** Always-on draws no date, and waking draws it in: `CrossoverView` steps the
outline in over ~0.8s on a high-power timer (`REVEAL_STEPS` ticks of `REVEAL_TICK_MS`),
growing round each loop of the numeral from its top-left dot. Show and an Epix peek start
the same reveal. A watch face gets timers only while awake, which is the only time there
is an outline to draw.

Everything here was settled on the wrist, after the mockups had been wrong once. Don't
re-litigate any of it from a render:

- **The struck watermark did not read.** It drew one stroke of each numeral dot instead of
  two, 5 lit pixels against 9. The mockups said it read; on the watch it was invisible,
  because the window crosses rings whose colours and tiers already change under it, and a
  45% density step is lost in that. Rotating the numeral's dots was tried before that and
  was a sheen even in the mockups.
- **The line runs through the dot centres, never along cell edges.** An outline five
  pixels off every dot fights the grid. One through the centres *is* the grid, and on the
  Follow-the-rings field it still reads, though its joins float between the diagonal
  crosses rather than meeting arm tips.
- **65%, chosen on the watch from 50, 65 and 80 shown a minute apart**, and those three are
  what `dateOutline` offers. 100 was too obvious; 40 vanished outright, because the AMOLED
  crushes dark levels a monitor shows — so neither end is a choice. A level change goes
  through `Config.reload()`, whose forced clear is what re-inks every segment at the new
  brightness; `segInked` remembers dot colours, not inked ones, and would not notice.
- **A line fills only the gap between two arms** (`GAP_FROM`, `GAP_LENGTH`), drawn with
  `fillRectangle` because its extent is unambiguous where `drawLine`'s end pixel is not.
  At 65% a line painted over an arm repaints it dimmer, and the numeral's dots fade where
  they meet the outline. `theOutlineFillsOnlyTheGapsBetweenArms` holds it.

Five things are load-bearing and none is obvious:

- **Always-on draws no outline because a line does not escape itself under the drift.**
  `Drift` moves the field one `DOT` per phase, which takes a cross clean off its own pixels;
  a ten-pixel line shifted five pixels along itself overlaps. Measured: 1,872 outline pixels
  lit through two of the four phases, against one for every dot pixel. It also looks better
  — the field rests plain and waking connects the dots.
- **What clears the outline at sleep is the field print, not a line anyone wrote.** The
  outline lives in the persistent frame buffer until something clears it. The day is in
  the field print only while the frame carries the date, so falling asleep drops the slot
  to 0, the print moves, and the always-on frame is drawn from black.
  `fallingAsleepClearsTheOutline` asserts both halves; let that transition through as a
  partial redraw and the outline stays lit through always-on at twice any dot's duty.
- **The trace never runs in `onUpdate`.** `DateGlyph.trace()` is cheap on its own and
  still tripped the watchdog in the simulator when it ran inside the same callback as the
  full redraw a new day always is. `startReveal()` calls `ensureTraced()` from the wake,
  show and peek callbacks, each with its own budget. The honest cost: **a date that rolls
  over while the face is awake draws its dots but no outline until the next wake.**
- **The renderer records each numeral dot's colour as it draws it** (`DateGlyph.colours`),
  and the outline is inked in those colours after the renderer, into the same buffer. That
  colour is everything the dot loop decided — tier, ramp, block level, hand — which nothing
  outside the loop could cheaply say again. The cursor that finds the numeral's dots is a
  *sorted list of indices* re-seeded per ring from `firstFor`, and **it advances inside the
  branch that records**, which only works because the delta redraw never skips a numeral
  dot (`i != glyphNext` in its condition). `aDeltaNeverSkipsANumeralDot` is the guard.
  Upright, that is the comparison the struck watermark already cost every dot; on the turned
  field it is new — ROADMAP has the A/B.
- **The day is in the *field* print, so midnight clears the screen**, which is the only
  thing that removes yesterday's outline from the gaps a repaint never touches.
  `DateGlyph.today()` keys on the epoch second divided by a day, so `Gregorian.info` is
  called once a day rather than on every frame including the skipped ones.

At `SCALE = 2` every stroke of the font is two dots wide, so every numeral dot is on the
edge: the outline is one or more closed loops passing through each numeral dot exactly once,
as many segments as dots. `theOutlineIsClosedThroughEveryNumeralDot` asserts that for all 31
days, and `theDateMatchesTheMockup` pins the counts to `tools/mockup.py`, which traces the
same edges with the same rule. The window is 14x10 cells at `(ORIGIN_COL, ORIGIN_ROW) = (12,
23)` — horizontally centred, lower half, the only placement of that size clearing the hand
pivot; `everyWatermarkCellHoldsADot` fails if a nudge costs the numeral a hole.

`DotGrid.generation` exists for this and nothing else. `build()` reuses its arrays when the
lattice has not changed size, which is every rebuild there is, so nothing about the arrays
says they have been rewritten — and a cache of *indices* into them cannot notice. The
counter is what `DateGlyph` reads; `aRebuiltLatticeRefreshesTheWatermark` holds it there.

The light it costs is awake-only, so it is not measured against the always-on budget:
about +0.15 points on the default field, on both rotations.

### The 10% luminance budget

Garmin blanks an always-on face that exceeds 10% of screen luminance. Current design sits at
~4.8% active / ~4.6% always-on, ~5.7% worst case on Terrain, and lower on every other theme —
**and those figures hold on every screen size**, because `PITCH` and `DOT` do not move with
the screen (see *One face, five watches*). Drawn hands add 0.05-0.16 points on top, taking
the worst theme to 6.16%.
`everyThemeFitsTheAlwaysOnBudget` is what checks the others, since
`alwaysOnWorstCaseFitsBudget` only ever measures the persisted one. It asserts it in the
test suite; `tools/luminance.py` and the simulator's **File → View Screen Heat Map** measure it.

Awake and always-on share their *filled* colours and differ only in the unfilled tier
(`WEAK_ACTIVE` 0.55 vs `WEAK_ALWAYS_ON` 0.45). `Palette.LIFT` is 1.0 — scaling up would clamp
channels and shift hue rather than brighten.

There is a **fourth tier**, `Palette.dimOf` at `WEAK_UNKNOWN` 0.25, for an hour the forecast
said nothing about. The face never draws black, so a dry hour is the unfilled tier rather
than darkness, and "no forecast" needs a third value or it reads as a confident forecast of
no rain. 0.25 is chosen against **always-on**, the tighter pair: `0.45 / 1.82` reproduces the
lit-to-unfilled step one rung down. Being *darker* than unfilled is what makes it free —
luminance only falls, so no theme needs re-measuring — and `everyThemeKeepsTheTierOrder` now
walks it alongside the other three.

There is a **third palette table**, `Palette.heldBack`, for always-on with the fills held back.
Nothing is lit in that mode, so the unfilled tier is the whole image rather than a backdrop, and
`WEAK_HELD_BACK` lifts it — written as `WEAK_ACTIVE`, not as a value, because the decision is to
match the awake field so the background does not shift on a wrist raise. It moves that frame from
~2.6% to ~3.2%, against ~4.6–5.0% for the same mode with its data shown. Staying clearly below
that data-shown figure, not the 10% budget, is the real bound on how far this tier may be lifted,
and `heldBackFillsCutAlwaysOnLuminance` is what holds the line.

### Device facts that constrain the design

Round AMOLED throughout, ~325ppi throughout, 123k of watch-face memory granted on all five,
and the same 240,000-count watchdog. What differs:

    device                    screen   touch  hands     launcher icon
    instinctcrossoveramoled   390      no     physical  38x38
    epix2pro42mm              390      yes    drawn     60x60
    epix2 / epix2pro47mm      416      yes    drawn     60x60
    epix2pro51mm              454      yes    drawn     60x60

The Crossover's 21px hub and two analogue hands (hour 131px, minute 176px reach, 28px wide,
minute hand mid-grey `0x808080`) sit over the glass — **the grey minute hand is the real
palette constraint**, and it is why the drawn hands reuse that exact pair rather than
choosing: every theme was designed to survive it. Hand and display geometry comes from
`~/.Garmin/ConnectIQ/Devices/<device>/simulator.json`; keep it sourced from there rather than
hard-coding new numbers, and note the Epix profiles carry **no `analogHands` block at all**.

The Epix family is touch-capable where the Crossover is not. `SettingsMenu` needs nothing for
it — Menu2 handles touch itself — but it is no longer true that this face only ever sees
buttons.

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
