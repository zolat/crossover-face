# Crossover Face

A Connect IQ watch face for the **Garmin Instinct Crossover AMOLED** — a dot-matrix field
where the data *is* the background. Each dot carries its stat's colour top to bottom; the
fill level changes intensity rather than presence, so the face never restructures itself,
it just saturates through the day. Nothing floats above the dots, which is why the watch's
physical analogue hands sweep over it without ever obscuring anything.

## Quick start

```sh
make build      # compile for the simulator
make sim        # launch the simulator and sideload
make install    # sideload onto a USB-connected watch
make test       # run the unit tests
make package    # signed .iq for the Connect IQ Store
make sdk-info   # show resolved SDK path, device and key
```

## Prerequisites

| | |
|---|---|
| Java | 17+ (built and tested on OpenJDK 21, arm64) |
| Connect IQ SDK | 9.2.0 |
| Device files | `instinctcrossoveramoled` |
| Signing key | RSA 4096, PKCS#8 DER |
| Editor | VS Code + the `garmin.monkey-c` extension (optional) |

### Setting up from scratch on macOS

```sh
# 1. Java. The temurin cask needs sudo; this route does not.
brew install openjdk@21
mkdir -p ~/Library/Java/JavaVirtualMachines
ln -sfn /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk \
        ~/Library/Java/JavaVirtualMachines/openjdk-21.jdk
java -version                     # should report 21.x

# 2. SDK manager CLI (Homebrew's formula/cask are both broken as of 0.8.4 —
#    the formula wants a newer Xcode, the cask has a bad symlink)
curl -fsSL -o /tmp/ciq.tar.gz \
  https://github.com/lindell/connect-iq-sdk-manager-cli/releases/download/v0.8.4/connect-iq-sdk-manager-cli_0.8.4_Darwin_ARM64.tar.gz
tar -xzf /tmp/ciq.tar.gz -C /tmp
install /tmp/connect-iq-sdk-manager /opt/homebrew/bin/

# 3. Accept the licence and sign in with your Garmin account
connect-iq-sdk-manager agreement view
connect-iq-sdk-manager agreement accept
connect-iq-sdk-manager login

# 4. SDK + device
connect-iq-sdk-manager sdk set 9.2.0
connect-iq-sdk-manager device download -d instinctcrossoveramoled --include-fonts

# 5. THE GOTCHA — see below
mkdir -p ~/Library/Application\ Support/Garmin
ln -sfn ~/.Garmin/ConnectIQ ~/Library/Application\ Support/Garmin/ConnectIQ

# 6. Developer signing key
mkdir -p ~/.Garmin/ConnectIQ && cd ~/.Garmin/ConnectIQ
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
        -in developer_key.pem -out developer_key.der -nocrypt
chmod 600 developer_key.pem developer_key.der
```

Garmin's GUI SDK Manager (`/Applications/SdkManager.app`) does the same job through a UI if
you prefer it — steps 3–5 are then clicks, but step 5 still applies.

### The two macOS gotchas

**1. The compiler and the CLI disagree about where devices live.** On macOS `monkeyc`
resolves devices from `~/Library/Application Support/Garmin/ConnectIQ/`, but
`connect-iq-sdk-manager` writes to `~/.Garmin/ConnectIQ/`. Without the symlink in step 5
every build fails with:

```
ERROR: Invalid device id specified: 'instinctcrossoveramoled'.
```

despite the device being installed. (Both paths are visible as string constants inside
`monkeybrains.jar`; the macOS branch picks the first.)

**2. Homebrew's `temurin` cask needs sudo**, because it installs a `.pkg` into
`/Library/Java/JavaVirtualMachines`. The keg-only `openjdk@21` formula plus a symlink into
the *user's* `~/Library/Java/JavaVirtualMachines` achieves the same thing without
elevation, and `/usr/libexec/java_home` finds it — so GUI apps like VS Code and the
simulator pick it up too, not just the shell.

Unrelated but worth knowing: **avoid apostrophes anywhere in the project path.** The Monkey
C compiler fails on them, which bites people whose iCloud folder is named
`Documents - Someone's MacBook`.

## The device

| | |
|---|---|
| Product id | `instinctcrossoveramoled` |
| Screen | 390 × 390, round, AMOLED, 65536 colours |
| Family | `round-390x390` |
| Connect IQ | 6.0.2 |
| Input | buttons only — `enter, up, menu, down, esc`. **No touch.** |
| Watch-face memory | 131,072 bytes |
| Part number | 006-B4678-00 |

Reference data lives in `~/.Garmin/ConnectIQ/Devices/instinctcrossoveramoled/`
(`compiler.json`, `simulator.json`, `device.png`) and the SDK ships a full page at
`doc/docs/Device_Reference/instinctcrossoveramoled.html`.

### Analogue hands

The watch has real hands over the display. They are **not** something the face must design
around — the watch parks and sweeps them itself — but their geometry matters, and the
simulator draws them, so what you see in the simulator is what you get. From
`simulator.json`:

| | |
|---|---|
| Hub (permanently covers the centre) | radius 21 px |
| Hour hand | 131 px reach, 28 px wide, white with black outline |
| Minute hand | 176 px reach, 28 px wide, **grey `0x808080`** with white outline |
| Default park | 270° / 90° — flat, revealing the face |

The grey minute hand is the one real constraint on the palette: mid-grey elements crossing
mid-grey dots would disappear.

## Frame budget

A watch face gets a hard watchdog allowance per `onUpdate`, and this face draws ~1,100 dots
every frame in interpreted bytecode. Working out each dot's ring and position inside that
loop **tripped the watchdog outright** — `Code Executed Too Long`, thrown from
`StatMap.classify()`. The face would not load at all.

None of that work depends on the data, only on the geometry and the layout. So `DotGrid`
computes it once and caches parallel arrays of dx, dy, ring and position; `Config.reload()`
rebuilds them whenever the layout changes. `MatrixRenderer` is then a flat walk with no
calls in the inner loop, and `setColor` is only issued when the colour actually differs.

Measured in the simulator with `System.getTimer()` around `onUpdate`:

| | Frame time |
|---|---|
| Before | watchdog trip — never completed |
| After | **avg 36ms, peak 44ms** over 21 frames |

Two rules keep it there: **nothing is computed in the loop that `DotGrid` could compute
once, and nothing calls out of the loop that could be an array lookup.** If you raise the
dot count, re-measure — instrument `onUpdate` and read `monkeydo`'s output, which streams
`println` straight to the terminal.

## Dots

Dots are **crosses, not squares** — a 5px cross lights 9 pixels where a filled square of
the same extent lights 25. That buys density: at a 10px pitch the face carries ~1,100 dots
against ~570 of squares, *and* costs less light. The finer grain reads as instrument
texture rather than a chunky LED panel.

The renderer only calls `setColor` when the colour actually changes. Runs of dots share a
colour, especially in the band layouts, so with ~1,100 dots a frame this saves far more
calls than it costs.

## Burn-in drift

The lattice walks a four-phase cycle, changing every two minutes
(`source/matrix/Drift.mc`). The offsets are **-2 and +3 on each axis**, and that asymmetry
is not arbitrary. At a 10px pitch with 5px dots there is exactly 5px of slack between one
dot and its neighbour, and two competing demands on it:

- a dot must move **at least DOT (5px)** or it keeps sharing pixels with *itself*;
- it must move **no more than the slack** or it starts landing on its *neighbour*.

Offsets of -2 and +3 are exactly 5px apart and consume exactly the slack, satisfying both.
A symmetric ±3 spans 6px and collides with the next dot along — which is precisely what
happened when the pitch tightened from 14 to 10, and what
`driftDutyCycleIsOnePhaseInFour` now catches. That test lays out a 3×3 block of dots and
counts how many phases light each pixel, because a single dot in isolation always looks
fine; it is the neighbours that break the guarantee.

Drift is applied when drawing, never when deciding which dots exist, so the field
translates rigidly instead of popping dots in and out at the edge.

Measured over a full cycle by `tools/mockup.py`: **worst duty cycle 1 phase in 4.** No
pixel is lit in more than one phase, so each rests 75% of the time and is never lit for
more than two minutes running.

## AMOLED always-on rules

Garmin turns the screen off if an always-on watch face burns too much of the panel. On this
generation the rule is **under 10% of the screen's luminance** (older Venu-era devices also
enforced "no pixel lit longer than 3 minutes"). Power mode is read at run time:

```monkeyc
System.getDisplayMode()   // DISPLAY_MODE_HIGH_POWER | LOW_POWER | OFF, API 5.0.0+
```

`CrossoverView` uses this to pick which palette `MatrixRenderer` draws with, falling back to
`DeviceSettings.requiresBurnInProtection` plus sleep state on pre-5.0.0 devices. There is
one renderer rather than two, because awake and always-on differ only by the colour table.

Two ways to check a design against the budget:

- **`python3 tools/luminance.py <face.png>`** — measures mean relative luminance over the
  circular screen area and prints it against the 10% budget.
- **Simulator → File → View Screen Heat Map** — Garmin's own burn-in simulation, which
  compresses a 24-hour run into minutes. Only enabled for watch faces on devices with
  screen protection, which this one has.

Current design: **~4.8% active, ~4.6% always-on**, and **~5.7% at the worst case** of every
ring reading full.

The two modes now draw the **same filled colours** and differ only in their unfilled tier
(`WEAK_ACTIVE` 0.55 against `WEAK_ALWAYS_ON` 0.45). `Palette.LIFT` is 1.0: an earlier
palette was dark enough that always-on needed lifting to survive the panel's own dimming,
but green and yellow now sit at or near a full channel, so scaling up would clamp and shift
the hue rather than brighten it. `tools/mockup.py` agrees
to within a tenth of a percent, and `make test` asserts the lattice matches it exactly, so
the mockups stay an honest preview rather than drifting into wishful thinking.

## Installing on the watch

```sh
make install
```

**This device generation is MTP-only.** Garmin moved away from USB mass storage, so the
watch never appears in `/Volumes` and there is nothing to `cp` to. The USB Mode prompt on
the watch offers two things, and neither is mass storage:

| Answer | What you get | Mountable? |
|---|---|---|
| **Yes, use MTP** | MTP (`idProduct 0x5246`) — what you want | No, but MTP clients can reach it |
| No | Garmin's proprietary protocol (`idProduct 0x0003`) | No, and it may not even charge |

So answer **yes** to *Use MTP?*, then `make install` opens [OpenMTP](https://openmtp.ganeshrvel.com/)
and reveals the `.prg` in Finder. Drag it into **GARMIN/Apps/** — that one file is all the watch needs. The
`.prg.debug.xml` beside it stays on your Mac; it symbolicates crash logs pulled from
`GARMIN/Apps/LOGS/`. Then on the watch hold **MENU → Watch Face → Crossover Face**.

`libmtp`'s CLI (`mtp-sendfile`) does *detect* the watch, but cannot write to it: Garmin's
MTP implementation does not support the bulk-metadata call libmtp uses to resolve a parent
folder, so every send fails with `could not get storage id from parent id`. OpenMTP walks
the tree itself and works. If you want to confirm the Mac sees the watch at all:

```sh
ioreg -p IOUSB -w0 -l | grep -E '"idVendor"|"idProduct"'   # Garmin is idVendor 2334 (0x091E)
mtp-detect | grep -i "friendly name"                       # should say Instinct Crossover AMOLED
```

`make install` still copies directly if a mass-storage volume *is* present, so it keeps
working for older Garmin devices.

## Settings

All settings are changeable **on the watch itself** — hold **MENU → Watch Face → Crossover
Face → Settings**. That matters because phone-side settings are unreliable for a sideloaded
app. `AppBase.getSettingsView()` provides this (`source/settings/`); watch faces cannot
normally accept input, and that hook is the sanctioned exception. The same settings appear
in Garmin Connect or Garmin Express if the face is ever installed from the store.

### Ring data

The face has four rings, and **each one is independently assigned to a source**:

| Source | Shape | Where it comes from |
|---|---|---|
| Steps | level | `ActivityMonitor` steps ÷ your step goal |
| Heart rate | level | `Activity.currentHeartRate`, resting → 180bpm |
| Battery | level | `System.getSystemStats()` |
| Body Battery | level | `SensorHistory` |
| Temperature range | **range** | `Weather` today's low → high, on a 0–60°C scale |
| Chance of rain | level | `Weather.precipitationChance` |
| Off | — | nothing |

Every source reports a **span** — a start and an end, both 0.0–1.0 — rather than a single
level. Levels are just spans that start at zero. That one shape is why temperature, which
is a genuine range, works in every layout without the layouts knowing anything about it: a
level fills from the origin, a range floats between its ends. In bands a range reads as a
slab; in rings, as an arc.

Temperature is the one source drawn on a ramp rather than a flat hue — ice through amber to
rust — so the band reads as a temperature rather than just a length.

Its **0–60°C scale is deliberately far wider than any weather needs**: it puts one degree on
every minute mark, so the band can be read off the dial exactly the way you read the minute
hand. 18°C sits where :18 does. A tighter scale would use the ring better and be harder to
read.

The scale **wraps rather than clamps**, which the minute-mark mapping implies: −5°C belongs
at :55, five degrees anticlockwise of twelve, exactly where minute 55 sits. Clamping instead
would fold every sub-zero reading onto twelve and quietly show a −5→3° day as 0→3° — a wrong
reading rather than a missing one. A frosty range therefore has its start *after* its end,
and `StatMap.isLit()` handles that case: a span whose end precedes its start wraps past the
origin. (−5°C and 55°C share a position; nothing confuses them in practice, and the scale
already wraps 60 onto 0 the same way.)

### Layout

| Layout | Ring index | Position runs |
|---|---|---|
| **Bands — fill upward** (default) | column, left to right | up from the rim |
| **Bands — fill from centre** | column, left to right | out from the midline |
| **Rings — fill clockwise** | radius, outer to inner | clockwise from twelve |

### Behind hands

Off (default), White, or Dark. Dots under the analogue hands are recoloured so the hands
read against a plain corridor instead of a field of colour. **Awake only** — in always-on it
would spend luminance on a detail nobody is looking at.

Two things make it work:

- `View.setClockHandPosition({:clockState => ANALOG_CLOCK_STATE_SYSTEM_TIME})` is called on
  wake, so the hands are known to be showing the time rather than parked. That API exists
  on exactly two devices, both Crossovers.
- The footprint is the hands' own outline **exactly**, no wider — matching how Garmin's own
  faces do it. What is lit is what sits *behind* the hand, not a cleared corridor around it.
  The hands stand above the glass, so what you see is the lit area emerging along their
  edge. The mockups cannot show this: they draw the hands as flat opaque shapes with no
  gap, so the backing looks invisible there. Only the watch shows it properly.

Properties live in `resources/properties.xml`, are surfaced by
`resources/settings/settings.xml`, and are read by `Config.reload()`. Anything missing or
out of range falls back to its default rather than throwing — there are tests for that.

## Frame budget

A watch face gets a hard watchdog allowance per `onUpdate`, and this face draws ~1,100 dots
every frame in interpreted bytecode. Working out each dot's ring and position inside that
loop **tripped the watchdog outright** — `Code Executed Too Long`, thrown from
`StatMap.classify()`. The face would not load at all.

None of that work depends on the data, only on the geometry and the layout. So `DotGrid`
computes it once and caches parallel arrays of dx, dy, ring and position; `Config.reload()`
rebuilds them whenever the layout changes. `MatrixRenderer` is then a flat walk with no
calls in the inner loop, and `setColor` is only issued when the colour actually differs.

Measured in the simulator with `System.getTimer()` around `onUpdate`:

| | Frame time |
|---|---|
| Before | watchdog trip — never completed |
| After | **avg 36ms, peak 44ms** over 21 frames |

Two rules keep it there: **nothing is computed in the loop that `DotGrid` could compute
once, and nothing calls out of the loop that could be an array lookup.** If you raise the
dot count, re-measure — instrument `onUpdate` and read `monkeydo`'s output, which streams
`println` straight to the terminal.

## Dots

Dots are **crosses, not squares** — a 5px cross lights 9 pixels where a filled square of
the same extent lights 25. That buys density: at a 10px pitch the face carries ~1,100 dots
against ~570 of squares, *and* costs less light. The finer grain reads as instrument
texture rather than a chunky LED panel.

The renderer only calls `setColor` when the colour actually changes. Runs of dots share a
colour, especially in the band layouts, so with ~1,100 dots a frame this saves far more
calls than it costs.

## Burn-in drift

The lattice walks a four-phase cycle, changing every two minutes
(`source/matrix/Drift.mc`). The offsets are **-2 and +3 on each axis**, and that asymmetry
is not arbitrary. At a 10px pitch with 5px dots there is exactly 5px of slack between one
dot and its neighbour, and two competing demands on it:

- a dot must move **at least DOT (5px)** or it keeps sharing pixels with *itself*;
- it must move **no more than the slack** or it starts landing on its *neighbour*.

Offsets of -2 and +3 are exactly 5px apart and consume exactly the slack, satisfying both.
A symmetric ±3 spans 6px and collides with the next dot along — which is precisely what
happened when the pitch tightened from 14 to 10, and what
`driftDutyCycleIsOnePhaseInFour` now catches. That test lays out a 3×3 block of dots and
counts how many phases light each pixel, because a single dot in isolation always looks
fine; it is the neighbours that break the guarantee.

Drift is applied when drawing, never when deciding which dots exist, so the field
translates rigidly instead of popping dots in and out at the edge.

Measured over a full cycle by `tools/mockup.py`: **worst duty cycle 1 phase in 4.** No
pixel is lit in more than one phase, so each rests 75% of the time and is never lit for
more than two minutes running.

## AMOLED always-on rules

Garmin turns the screen off if an always-on watch face burns too much of the panel. On this
generation the rule is **under 10% of the screen's luminance** (older Venu-era devices also
enforced "no pixel lit longer than 3 minutes"). Power mode is read at run time:

```monkeyc
System.getDisplayMode()   // DISPLAY_MODE_HIGH_POWER | LOW_POWER | OFF, API 5.0.0+
```

`CrossoverView` uses this to pick which palette `MatrixRenderer` draws with, falling back to
`DeviceSettings.requiresBurnInProtection` plus sleep state on pre-5.0.0 devices. There is
one renderer rather than two, because awake and always-on differ only by the colour table.

Two ways to check a design against the budget:

- **`python3 tools/luminance.py <face.png>`** — measures mean relative luminance over the
  circular screen area and prints it against the 10% budget.
- **Simulator → File → View Screen Heat Map** — Garmin's own burn-in simulation, which
  compresses a 24-hour run into minutes. Only enabled for watch faces on devices with
  screen protection, which this one has.

Current design: **~4.8% active, ~4.6% always-on**, and **~5.7% at the worst case** of every
ring reading full.

The two modes now draw the **same filled colours** and differ only in their unfilled tier
(`WEAK_ACTIVE` 0.55 against `WEAK_ALWAYS_ON` 0.45). `Palette.LIFT` is 1.0: an earlier
palette was dark enough that always-on needed lifting to survive the panel's own dimming,
but green and yellow now sit at or near a full channel, so scaling up would clamp and shift
the hue rather than brighten it. `tools/mockup.py` agrees
to within a tenth of a percent, and `make test` asserts the lattice matches it exactly, so
the mockups stay an honest preview rather than drifting into wishful thinking.

## Installing on the watch

```sh
make install
```

**This device generation is MTP-only.** Garmin moved away from USB mass storage, so the
watch never appears in `/Volumes` and there is nothing to `cp` to. The USB Mode prompt on
the watch offers two things, and neither is mass storage:

| Answer | What you get | Mountable? |
|---|---|---|
| **Yes, use MTP** | MTP (`idProduct 0x5246`) — what you want | No, but MTP clients can reach it |
| No | Garmin's proprietary protocol (`idProduct 0x0003`) | No, and it may not even charge |

So answer **yes** to *Use MTP?*, then `make install` opens [OpenMTP](https://openmtp.ganeshrvel.com/)
and reveals the `.prg` in Finder. Drag it into **GARMIN/Apps/** — that one file is all the watch needs. The
`.prg.debug.xml` beside it stays on your Mac; it symbolicates crash logs pulled from
`GARMIN/Apps/LOGS/`. Then on the watch hold **MENU → Watch Face → Crossover Face**.

`libmtp`'s CLI (`mtp-sendfile`) does *detect* the watch, but cannot write to it: Garmin's
MTP implementation does not support the bulk-metadata call libmtp uses to resolve a parent
folder, so every send fails with `could not get storage id from parent id`. OpenMTP walks
the tree itself and works. If you want to confirm the Mac sees the watch at all:

```sh
ioreg -p IOUSB -w0 -l | grep -E '"idVendor"|"idProduct"'   # Garmin is idVendor 2334 (0x091E)
mtp-detect | grep -i "friendly name"                       # should say Instinct Crossover AMOLED
```

`make install` still copies directly if a mass-storage volume *is* present, so it keeps
working for older Garmin devices.

## Settings

The face ships with one user-facing setting — the layout — and it can be changed **on the
watch itself**, which matters because phone-side settings are unreliable for a sideloaded
app. From the watch face, hold **MENU → Watch Face → Crossover Face → Settings**.

`AppBase.getSettingsView()` provides this (`source/settings/LayoutMenu.mc`). Watch faces
cannot normally accept input; that hook is the sanctioned exception. The same setting also
appears in Garmin Connect or Garmin Express if the face is installed from the store.

### Layout

| Layout | Behaviour |
|---|---|
| **Bands — fill upward** (default) | Column picks the stat, fill rises from the rim |
| **Bands — fill from centre** | As above, but fill grows out from the midline |
| **Rings — fill clockwise** | Radius picks the ring, fill sweeps clockwise from 12 |

### Behind hands

Off (default), White, or Dark. When on, dots lying under the analogue hands are recoloured
so the hands read against a plain corridor instead of a field of colour. **Awake only** — in
always-on it would spend luminance on a detail nobody is looking at.

Two things make this work:

- `View.setClockHandPosition({:clockState => ANALOG_CLOCK_STATE_SYSTEM_TIME})` is called on
  wake, so the hands are known to be showing the time rather than parked somewhere else.
  That API exists on exactly two devices, both Crossovers.
- The footprint is the hands' own outline **exactly**, no wider — matching how Garmin's own
  faces do it. What is lit is what sits *behind* the hand, not a cleared corridor around it.
  The hands stand above the glass, so what you see is the lit area emerging along their
  edge. The mockups cannot show this: they draw the hands as flat opaque shapes with no
  gap, so the backing looks invisible there. Only the watch shows it properly.

Properties live in `resources/properties.xml`, are surfaced by
`resources/settings/settings.xml`, and are read by `StatMap.load()`. An out-of-range or
missing value falls back to its default rather than throwing — there are tests for that.

To try the layouts in the simulator without touching settings on a phone:
**File → Edit Persistent Storage → Edit Application.Properties data**.

## Design tooling

```sh
python3 tools/mockup.py [outdir]     # default: build/mockups
```

Renders the face at true 390 × 390, composites it into Garmin's device art at the exact
display offset from `simulator.json`, and overlays the hand polylines — so mockups show the
watch rather than an abstract grid. It reads all geometry from the installed device files,
so nothing is hard-coded to drift.

Iterating on colour through a compile-and-sideload loop costs about a minute a go; this
costs a second, which is why the palette gets settled here before any Monkey C is written.

## Layout

```
manifest.xml          app id, target product, min API level
monkey.jungle         build config (strict type checking is on)
source/
  CrossoverApp.mc     app lifecycle
  CrossoverView.mc    picks a renderer based on power mode — no drawing
  data/WatchData.mc   device state, formatted. Pure queries, no drawing
  matrix/DotGrid.mc   lattice geometry: pitch, circle clip, hub
  matrix/StatMap.mc   dot -> ring mapping and span test; the layout seam
  matrix/Drift.mc     burn-in mitigation cycle
  matrix/HandBacking.mc  which dots sit under the analogue hands
  data/Source.mc      what a ring can be assigned to; spans and hues
  data/WeatherData.mc today's temperature range and rain chance
  render/Config.mc    reloads settings and palette together
  settings/           on-device layout picker
  render/Palette.mc   four hues, two tiers, two power modes
  render/MatrixRenderer.mc  draws the field with a given palette
  tests/              geometry, mapping and luminance-budget tests
resources/
  drawables/          launcher icon
  properties.xml      the layout setting's stored value
  settings/           how that setting is presented in Garmin Connect
  strings/            app name and setting labels
tools/                mockup + luminance measurement
```

The signing key is deliberately outside the repo, and `.gitignore` covers `*.der` / `*.pem`
as a second line of defence. **Never commit it** — it is the identity your published apps
are signed with, and it cannot be reissued for apps already in the store.
