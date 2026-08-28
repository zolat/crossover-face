# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

A Connect IQ watch face for the **Garmin Instinct Crossover AMOLED**, written in Monkey C. The
face is a dot-matrix field where the data *is* the background: four rings/bands of ~1,100 dots,
each dot coloured by the source its ring is assigned to.

`README.md` is the authority on toolchain setup, MTP sideloading and design rationale. This file
covers the working knowledge that spans files and is easy to break.

## Commands

```sh
make build      # debug .prg for the simulator
make sim        # build, start the simulator if needed, sideload, stream println
make test       # build with -t, run the 21-test suite in the simulator
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

### Command gotchas

- **There is no lint or typecheck step.** `monkey.jungle` sets `project.typecheck = strict` and
  the Makefile passes `-w`, so a clean `make build` *is* the type check. Don't go looking for one.
- **`monkeydo` exits non-zero even when every test passes**, which is why `make test` greps for
  `^PASSED` and ignores the exit code. Never judge a raw `monkeydo` run by its status code — read
  the summary line.
- **A killed simulator looks like a test failure.** If `make test` prints nothing but
  `TESTS FAILED`, the simulator died mid-run (a parallel session restarting it will do this).
  Re-run before believing it.
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

Geometry: `DotGrid` (the lattice, cached), `StatMap` (dot → ring + position — the layout seam),
`Drift` (burn-in cycle), `HandBacking` (which dots sit under the physical hands).

### The frame budget dominates every decision here

~1,100 dots are drawn per `onUpdate` in interpreted bytecode against a hard watchdog. An earlier
version that computed each dot's ring and position inline **tripped the watchdog outright** and
the face would not load. The rule:

> Nothing is computed in the render loop that `DotGrid.build()` could compute once, and nothing
> calls out of the loop that could be an array lookup.

`DotGrid` caches parallel arrays (`xs`, `ys`, `ringOf`, `positionOf`, `armOf`) built once per
layout change; `MatrixRenderer` is a flat indexed walk. The single deliberate exception is
`StatMap.isLit()`, called per dot (~6ms/frame) so the lit test has one definition shared with the
tests. Current cost: avg 36ms, peak 44ms. **If you add per-dot work or raise the dot count,
re-measure** — wrap `onUpdate` in `System.getTimer()` and read `make sim` output.

Caching the field to a `BufferedBitmap` is not an option: 390×390 at 16bpp is ~304KB against a
128KB watch-face memory budget.

### Config.reload() ordering is load-bearing

`StatMap.load()` → `Palette.build()` → `DotGrid.build()`. Palette hues depend on the ring
assignments, and DotGrid's cached ring/position/orientation depend on `StatMap.layout`. Anything
that changes a setting must go through `Config.reload()`, not a partial refresh.

### Every source reports a span, not a level

`Source.span()` returns `[start, end]`, both 0.0–1.0. Levels are just `[0.0, value]`. This is why
temperature — a genuine range — works in all three layouts without the layouts knowing about it.

`end < start` is **legal**: the temperature scale (0–60°C, one degree per minute mark) wraps
rather than clamps, so a sub-zero range runs from e.g. :55 round past twelve to :03.
`StatMap.isLit()` handles the wrap. Don't "fix" it by clamping — that silently misreports a
−5→3°C day as 0→3°C, and `subZeroWrapsBackPastTwelve` guards it.

### tools/mockup.py mirrors the Monkey C by hand

The Python mockup duplicates the lattice constants, `THEME`, `WEAK_*`/`LIFT`, `ARMS`, the three
layout mappings and the hand geometry. It is not generated. **Any change to geometry or palette
must land in both**, and `MatrixTest.EXPECTED_DOTS` (1112) plus the luminance tests pin the two
implementations together so they cannot drift silently.

### Settings live in four places that must stay in step

Stored values are **list indices**, so `resources/properties.xml`, `resources/settings/settings.xml`,
the enums in `StatMap`/`Source`, and the label arrays in `source/settings/SettingsMenu.mc` all
have to agree. Six properties today: `layout`, `handBacking`, `ring1`–`ring4`.

On-device settings exist because phone-side settings are unreliable for a sideloaded face;
`AppBase.getSettingsView()` is the sanctioned exception to "watch faces cannot take input".
`StatMap.readNumber()` falls back to the default for anything missing or out of range rather than
throwing. Menu sub-labels are refreshed in `onShow()` — Menu2 does not rebuild itself when a
sub-menu pops.

To switch layouts in the simulator: **File → Edit Persistent Storage → Edit Application.Properties**.

### The 10% luminance budget

Garmin blanks an always-on face that exceeds 10% of screen luminance. Current design sits at
~4.8% active / ~4.6% always-on, ~5.7% worst case. `alwaysOnWorstCaseFitsBudget` asserts it in the
test suite; `tools/luminance.py` and the simulator's **File → View Screen Heat Map** measure it.

Awake and always-on share their *filled* colours and differ only in the unfilled tier
(`WEAK_ACTIVE` 0.55 vs `WEAK_ALWAYS_ON` 0.45). `Palette.LIFT` is 1.0 — scaling up would clamp
channels and shift hue rather than brighten.

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
