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
make test-simctl # tests for tools/simctl (no simulator, no build needed)
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

**Each checkout gets its own simulator, so sessions no longer take turns.** The singleton
is a habit, not a constraint: `TMPDIR` moves the simulated device filesystem, `HOME` moves
the `Sim-$USER` file that refuses a second instance, and `SHELL_SERVER_PORT` moves the
control channel. `simctl/instance.py` sets all three, symlinking `~/.Garmin/ConnectIQ` back
so devices and the signing key stay shared. Two checkouts have run the full suite
concurrently, both green, neither touching the other or the lock.

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
and `tools/mockup.py` remain the authorities — both measure the dot field before hands.

> **An all-black capture means the Mac display slept**, which stops the Monkey C VM and
> makes a healthy face look like a hung test run. Worse, window capture then fails outright
> with *could not create image from window*, which reads as a missing Screen Recording
> permission. `window.display_is_asleep()` tests for it and `capture()` retries once after
> `caffeinate -u -t 5`. A locked screen cannot be woken from the shell.

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
dot, **22,240 bytes at 1112 dots**, five bytes a slot. `theDotCacheFitsItsShareOfMemory`
measures it and fails if a fifth per-dot array appears. That test has to drop the arrays'
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
`source/settings/SettingsMenu.mc` all have to agree. Eight properties today: `theme`,
`handBacking`, `alwaysOnFill`, `dotRotation`, `ring1`–`ring4`.

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

`Palette.THEMES` holds every theme's ring colours **flat** — `theme * THEME_COLOURS + n` —
for the reason `DotGrid.ARMS` is flat: a const array of arrays is further than Monkey C's
`const` is meant to go, and nesting it resolves in the simulator and comes back empty on the
watch. `RAMP_STOPS` is flat for the same reason.

The temperature ramp used to hard-code `THEME[2] → THEME[0] → THEME[3]`. Those indices carried
meaning — cold, mid, hot — not position, so each theme now names its own three as
`RAMP_STOPS[theme * RAMP_POINTS + n]`. They are **indices into the theme, not colours**: a ramp
stop *is* a ring colour, and writing the value a second time is how the two drift apart. That
frees the ring order to answer only to its real constraint, which is the CIELAB distance
between rings that sit next to each other (93 for Terrain, 118 for Activity).

Adding a theme means four things at once: the colours, its ramp stops, the range
`StatMap.load()` clamps `theme` to, and a label in `SettingsMenu.THEME_LABELS`. Miss the clamp
and the theme is simply unreachable, with no other symptom — `themeTablesCoverEveryTheme` is
the guard. `everyThemeFitsTheAlwaysOnBudget` and `everyThemeKeepsTheTierOrder` walk *every*
theme, because every other luminance test measures only whichever one is persisted.

**Four slots, but not necessarily four colours.** Frost, Lagoon and Nocturne are duotones:
two hues alternating, so slots 0 and 2 hold the same value and so do 1 and 3. Rings 1 and 3
never touch, so a repeat costs no legibility — and alternating makes *every* neighbour a hue
flip rather than a hue step, which is why the duotones measure 99–103 against Terrain's 93.
`everyThemeKeepsTheTierOrder` therefore compares **neighbours only**; it used to compare every
pair, which a duotone fails by design.

Two things about that are counterintuitive and were both settled by measurement:

- **The repeat has to be exact.** The obvious alternative — the same hue at two lightnesses,
  which keeps four distinct values and needs no test change — is the one arrangement that
  actually breaks the face. A dimmed `A` lands on top of `A`'s own unfilled tier, so ring 3
  *lit* becomes indistinguishable from ring 1 *unlit*: a CIELAB distance of 5–16, against
  61–67 for the four-hue themes. An exact repeat has no such collision, because the only pair
  it creates is `A` against `0.55·A` — the band-to-unfilled contrast every ring already lives on.
- **The temperature ramp is what actually constrains a duotone**, not ring contrast. With two
  hues there is no third colour to turn through, so the ramp runs straight from one to the
  other and *that blend is the middle of the scale*, where most readings sit. A complementary
  pair blends through grey and reads as no data: violet+lime drops to a chroma of 4,
  teal+coral to 14. `RAMP_LINEAR` (−1) in the mid slot is how a theme says it has only two
  stops, and `Palette.build()` substitutes the midpoint. Pairs whose blend goes grey are
  therefore unusable however well their rings separate — which is what kept several
  better-contrasting pairs out.

Activity's colours are not invented: they are the accent colours the watch itself uses, read
off the peak-chroma pixel of the device's own `nwidget_*.png` and `D_list_select_*.png`
swatches, whose hues agree to a tenth of a degree across both sets. Activity is the darker
theme throughout: worst-case always-on 4.82% against Terrain's 5.73%.

### Dot rotation is a render choice, not a cached one

`StatMap.rotation` decides only whether `MatrixRenderer` indexes `DotGrid.armOf` per dot or
uses the one upright cross it hoists. Which way a cross *would* point is geometry, so it is
cached either way and toggling the setting needs no rebuild. Do not move this into
`DotGrid.build()`: it would cost a full ~1100-dot rebuild per toggle, and the next step from
there is making the ring mapping conditional again. `rotationDoesNotReachTheCache` is the
guard. Every orientation lights nine pixels, so neither setting moves the luminance.

### The 10% luminance budget

Garmin blanks an always-on face that exceeds 10% of screen luminance. Current design sits at
~4.8% active / ~4.6% always-on, ~5.7% worst case on Terrain, and lower on every other theme —
`everyThemeFitsTheAlwaysOnBudget` is what checks the others, since
`alwaysOnWorstCaseFitsBudget` only ever measures the persisted one. It asserts it in the
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
