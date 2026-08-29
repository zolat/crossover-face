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
make install    # push straight onto a USB-connected watch, no GUI
make push       # same, skipping the mass-storage / USB-mode checks
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

## The startup watchdog

`onStart` runs against a **far tighter watchdog than a frame does**. The draw loop happily
walks ~1,100 dots and issues ~2,200 native calls in ~40ms; the *precompute* for those same
dots would not finish in `onStart` at all — it died with `Code Executed Too Long` inside
`DotGrid.build()`, and the face rendered two dots.

Tightening the arithmetic was not enough. In order, and each still tripping:

- inlining the per-dot maths so it stopped calling `StatMap` ~3,300 times;
- comparing squared distances so the ring index needs no square root;
- one angle per dot instead of two, in radians so `Math.toDegrees` went too;
- replacing `Math.atan2` entirely with a polynomial approximation (`Angle.turnOf`);
- deferring the whole build out of `onStart` into the first frame.

The work is simply too much for one synchronous pass on this hardware. So the cache is
**built in chunks across frames** (`DotGrid.CHUNK`): the face draws the dots it has and
fills in the rest over the next few updates, taking about eight frames from cold. The
layout rarely changes, so it is paid once.

`DotGrid.buildAll()` exists for tests and tooling. The face must never call it.

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

In the **rings layout each cross is turned to follow the circle it sits on** — one stroke
pointing out from the centre, the other across it. Crosses read as `+` on the axes and `×`
on the diagonals, which gives the field a radial structure matching what the layout is
actually showing. The band layouts have no circular structure to follow, so their crosses
stay upright.

A cross has 90° rotational symmetry, so four orientations at 22.5° apart cover every
distinct one — and at 5px that is about all the resolution there is anyway. Each dot's
orientation is precomputed in `DotGrid` alongside its ring and position, so the loop just
indexes a table (`DotGrid.ARMS`). Arms are scaled so the larger component is always half a
dot, keeping every orientation the same visual weight; scaling by true length would make
the diagonals visibly shorter.

Strokes are drawn with `drawLine`, which **measured faster than the two `fillRectangle`
calls it replaced** — 33.5ms against 39.7ms a frame. Rotation cost nothing; it saved time.

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
the hue rather than brighten it.

There is a **third tier for one mode only**: always-on with the fills held back. Nothing is
lit there, so the unfilled dots are not a backdrop to the data, they *are* the image, and
0.45 — chosen against a face that still had filled dots to carry it — read too dark on its
own. `Palette.WEAK_HELD_BACK` is defined as `WEAK_ACTIVE` rather than as a value, because the
decision is to **match the awake field**: the background then does not change brightness at
all when the wrist comes up, and a raise purely adds the filled dots with nothing shifting
underneath them. Measured on a real render that moves the frame from 2.6% to 3.2%, against
4.6–5.0% for the same mode showing its data — so the option still buys what it exists for.
The budget was never the constraint: every dot at full colour would still only reach 6.1%.

`tools/mockup.py` agrees
to within a tenth of a percent, and `make test` asserts the lattice matches it exactly, so
the mockups stay an honest preview rather than drifting into wishful thinking.

## Installing on the watch

```sh
make install    # build, check the watch is in MTP mode, push
make push       # build and push, skipping the checks
make reveal     # the old manual route, kept as a fallback
```

The face goes onto the watch **directly, with no GUI and no drag**. `make
install` quits OpenMTP first if it is running — only one process may claim the
watch's USB interface at a time — and afterwards verifies the file against the
watch's own directory listing rather than trusting the transfer to have worked.

**This device generation is MTP-only.** Garmin moved away from USB mass storage,
so the watch never appears in `/Volumes`. The USB Mode prompt on the watch offers
two things, and neither is mass storage:

| Answer | What you get | Mountable? |
|---|---|---|
| **Yes, use MTP** | MTP (`idProduct 0x5246`) — what you want | No, but MTP clients can reach it |
| No | Garmin's proprietary protocol (`idProduct 0x0003`) | No, and it may not even charge |

So answer **yes** to *Use MTP?*. If the watch is plugged in but sitting in
proprietary mode, `make install` says so and stops rather than failing obscurely.
Then on the watch hold **MENU → Watch Face → Crossover Face**. The
`.prg.debug.xml` beside the `.prg` stays on your Mac; it symbolicates crash logs
pulled from `GARMIN/Apps/LOGS/`.

### How the push works

macOS ships no usable MTP client, and **libmtp cannot talk to this watch**:
`libusb_claim_interface()` returns `-3`, access denied, because macOS's own Image
Capture daemon (`icdd`) holds the interface. `mtp-detect` therefore finds the
device and still cannot open it:

```
Device 0 (VID=091e and PID=5246) is UNKNOWN in libmtp v1.1.23.
error returned by libusb_claim_interface() = -3
LIBMTP PANIC: Unable to initialize device
```

OpenMTP works where libmtp does not — and its MTP engine is not the GUI. It is a
Go library, kalam, shipped inside the app bundle as a plain arm64 dylib with a C
ABI:

```
/Applications/OpenMTP.app/Contents/Resources/bin/arm64/kalam.dylib
```

`tools/mtp_push.py` drives that dylib directly through ctypes, so the build loop
gets the engine that already works with this watch, minus the drag. Nothing is
reimplemented and nothing is patched — the library is loaded out of the installed
app exactly as OpenMTP loads it, which means **OpenMTP is still a dependency, but
only as somewhere to find the library.** It never runs.

The JSON contract the driver speaks is transcribed from OpenMTP 3.3.0's own
bindings, which ship unminified inside `app.asar`, rather than guessed from the
exported symbols.

One trap worth recording, because the header actively misleads. The export reads:

```c
void Initialize(on_cb_result_t* onDonePtr);   // typedef void (*on_cb_result_t)(char*)
```

which looks like a pointer *to* a function pointer. It is not — kalam calls the
address it is handed. Passing `byref()` makes Go jump into the stack and abort
with a `SIGBUS` whose faulting pc is exactly the value passed. The function
pointer goes over directly.

The driver is usable on its own, and is the quickest way to see what is actually
on the watch:

```sh
python3 tools/mtp_push.py --info            # device, firmware, storages
python3 tools/mtp_push.py --ls /GARMIN/Apps # list a folder
```

If the push cannot run — no OpenMTP installed, watch in the wrong mode, anything
else — `make install` falls back to the old behaviour of opening OpenMTP and
revealing the `.prg` for a manual drag. `make install` also still copies directly
if a mass-storage volume *is* present, so it keeps working for older Garmin
devices.

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
| Temperature range | **range** + mark | `Weather` today's low → high, on a 0–60°C scale, with now marked |
| Chance of rain | level | `Weather.precipitationChance` |
| Intensity minutes | level | `ActivityMonitor` weekly active minutes ÷ your weekly goal |
| Seconds | level, **awake only** | `System.getClockTime()`, filling through each minute |
| Off | — | nothing |

Every source reports a **span** — a start and an end, both 0.0–1.0 — rather than a single
level. Levels are just spans that start at zero. That one shape is why temperature, which
is a genuine range, works in every layout without the layouts knowing anything about it: a
level fills from the origin, a range floats between its ends. In bands a range reads as a
slab; in rings, as an arc.

Temperature is the one source drawn on a ramp rather than a flat hue — ice through orchid to
rust — so the band reads as a temperature rather than just a length.

**Seconds is the one source that goes quiet.** It fills its ring from the origin and resets on
the minute — in the rings layout the leading edge of that fill is where a second hand would
point — but only while the watch is awake. Always-on is asked for one frame a minute, so a
per-second reading could only ever be stale there, and it is the mode the burn-in and
luminance rules are written against. Asleep the ring keeps its colour and shows no fill.

It is also the one source that costs something. The frame gate skips a frame whose fingerprint
matches the last one drawn, and a seconds span moves every tick, so with a seconds ring
assigned the face draws every awake second and the skip figure in **Frame cost** falls to
roughly nothing. That is the rate the face drew at before the gate existed, comfortably inside
the watchdog — but it is real battery, and it is the price of a second hand.

Its **0–60°C scale is deliberately far wider than any weather needs**: it puts one degree on
every minute mark, so the band can be read off the dial exactly the way you read the minute
hand. 18°C sits where :18 does. A tighter scale would use the ring better and be harder to
read.

A single near-white dot marks **where the current temperature falls** in that range. Without it a
day of 11→22°C looks identical at dawn and at noon, and the reading is already in the
conditions the low and high come from. The mark outranks the fill, so it stays legible when
now sits *outside* today's range — an overnight low or a stale forecast puts it there
routinely, and drawing it where it actually falls is the honest answer.

It is **awake only**, for the same reason the hand backing is: white is the most luminous
thing the face can draw, always-on is the mode measured against the burn-in budget, and it is
not the mode anyone is reading closely. It returns on a wrist raise.

**It is one dot, not a row of them.** A row was tried first and does not work: drawn out of
crosses it reads as a bumpy dotted band rather than a line, and in the rings layout the dots
inside the mark's window span three degrees of angle on a square lattice, so a radial run of
them staggers instead of lining up. Nothing made of lattice dots can be a straight line at an
arbitrary angle. One dot cannot be crooked.

That dot is **filled, not a cross**. Every other dot on the face is two thin strokes, so a
white cross among eleven hundred of them is just another cross — it was tried, and at arm's
length it vanished. A solid block is the only shape on the field that is not a cross, and
that, rather than the colour, is what makes it read as a mark. It costs nine lit pixels
becoming twenty-five, once.

Which dot is decided by `DotGrid.markedDot()`: of the dots inside a window around the marked
position, the one nearest the middle of its ring — the middle column of a band, the mid
radius of a ring — so the mark sits in the body of its ring rather than trailing off at the
rim. The window's half-width is **sized per ring**, because a lattice row is 0.026 of a
band's position but 0.076 of a turn on the innermost ring; one constant would fall clean
between dots there and the mark would not be drawn at all.

Two consequences worth knowing. The mark snaps to a dot, so it carries up to about half a
degree of rounding — the dial has 38 rows across 60°C. And in the band layouts the outer
bands do not reach the top and bottom of a round screen, so the lowest few degrees of the
leftmost band have no dots to mark, exactly as its fill has none; the rings layout has no
such gap.

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

## The startup watchdog

`onStart` runs against a **far tighter watchdog than a frame does**. The draw loop happily
walks ~1,100 dots and issues ~2,200 native calls in ~40ms; the *precompute* for those same
dots would not finish in `onStart` at all — it died with `Code Executed Too Long` inside
`DotGrid.build()`, and the face rendered two dots.

Tightening the arithmetic was not enough. In order, and each still tripping:

- inlining the per-dot maths so it stopped calling `StatMap` ~3,300 times;
- comparing squared distances so the ring index needs no square root;
- one angle per dot instead of two, in radians so `Math.toDegrees` went too;
- replacing `Math.atan2` entirely with a polynomial approximation (`Angle.turnOf`);
- deferring the whole build out of `onStart` into the first frame.

The work is simply too much for one synchronous pass on this hardware. So the cache is
**built in chunks across frames** (`DotGrid.CHUNK`): the face draws the dots it has and
fills in the rest over the next few updates, taking about eight frames from cold. The
layout rarely changes, so it is paid once.

`DotGrid.buildAll()` exists for tests and tooling. The face must never call it.

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

In the **rings layout each cross is turned to follow the circle it sits on** — one stroke
pointing out from the centre, the other across it. Crosses read as `+` on the axes and `×`
on the diagonals, which gives the field a radial structure matching what the layout is
actually showing. The band layouts have no circular structure to follow, so their crosses
stay upright.

A cross has 90° rotational symmetry, so four orientations at 22.5° apart cover every
distinct one — and at 5px that is about all the resolution there is anyway. Each dot's
orientation is precomputed in `DotGrid` alongside its ring and position, so the loop just
indexes a table (`DotGrid.ARMS`). Arms are scaled so the larger component is always half a
dot, keeping every orientation the same visual weight; scaling by true length would make
the diagonals visibly shorter.

Strokes are drawn with `drawLine`, which **measured faster than the two `fillRectangle`
calls it replaced** — 33.5ms against 39.7ms a frame. Rotation cost nothing; it saved time.

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
make install    # build, check the watch is in MTP mode, push
make push       # build and push, skipping the checks
make reveal     # the old manual route, kept as a fallback
```

The face goes onto the watch **directly, with no GUI and no drag**. `make
install` quits OpenMTP first if it is running — only one process may claim the
watch's USB interface at a time — and afterwards verifies the file against the
watch's own directory listing rather than trusting the transfer to have worked.

**This device generation is MTP-only.** Garmin moved away from USB mass storage,
so the watch never appears in `/Volumes`. The USB Mode prompt on the watch offers
two things, and neither is mass storage:

| Answer | What you get | Mountable? |
|---|---|---|
| **Yes, use MTP** | MTP (`idProduct 0x5246`) — what you want | No, but MTP clients can reach it |
| No | Garmin's proprietary protocol (`idProduct 0x0003`) | No, and it may not even charge |

So answer **yes** to *Use MTP?*. If the watch is plugged in but sitting in
proprietary mode, `make install` says so and stops rather than failing obscurely.
Then on the watch hold **MENU → Watch Face → Crossover Face**. The
`.prg.debug.xml` beside the `.prg` stays on your Mac; it symbolicates crash logs
pulled from `GARMIN/Apps/LOGS/`.

### How the push works

macOS ships no usable MTP client, and **libmtp cannot talk to this watch**:
`libusb_claim_interface()` returns `-3`, access denied, because macOS's own Image
Capture daemon (`icdd`) holds the interface. `mtp-detect` therefore finds the
device and still cannot open it:

```
Device 0 (VID=091e and PID=5246) is UNKNOWN in libmtp v1.1.23.
error returned by libusb_claim_interface() = -3
LIBMTP PANIC: Unable to initialize device
```

OpenMTP works where libmtp does not — and its MTP engine is not the GUI. It is a
Go library, kalam, shipped inside the app bundle as a plain arm64 dylib with a C
ABI:

```
/Applications/OpenMTP.app/Contents/Resources/bin/arm64/kalam.dylib
```

`tools/mtp_push.py` drives that dylib directly through ctypes, so the build loop
gets the engine that already works with this watch, minus the drag. Nothing is
reimplemented and nothing is patched — the library is loaded out of the installed
app exactly as OpenMTP loads it, which means **OpenMTP is still a dependency, but
only as somewhere to find the library.** It never runs.

The JSON contract the driver speaks is transcribed from OpenMTP 3.3.0's own
bindings, which ship unminified inside `app.asar`, rather than guessed from the
exported symbols.

One trap worth recording, because the header actively misleads. The export reads:

```c
void Initialize(on_cb_result_t* onDonePtr);   // typedef void (*on_cb_result_t)(char*)
```

which looks like a pointer *to* a function pointer. It is not — kalam calls the
address it is handed. Passing `byref()` makes Go jump into the stack and abort
with a `SIGBUS` whose faulting pc is exactly the value passed. The function
pointer goes over directly.

The driver is usable on its own, and is the quickest way to see what is actually
on the watch:

```sh
python3 tools/mtp_push.py --info            # device, firmware, storages
python3 tools/mtp_push.py --ls /GARMIN/Apps # list a folder
```

If the push cannot run — no OpenMTP installed, watch in the wrong mode, anything
else — `make install` falls back to the old behaviour of opening OpenMTP and
revealing the `.prg` for a manual drag. `make install` also still copies directly
if a mass-storage volume *is* present, so it keeps working for older Garmin
devices.

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
tools/
  mockup.py           design mockups, rendered into the device art
  luminance.py        always-on luminance budget measurement
  mtp_push.py         push the .prg to the watch over MTP, no GUI
```

The signing key is deliberately outside the repo, and `.gitignore` covers `*.der` / `*.pem`
as a second line of defence. **Never commit it** — it is the identity your published apps
are signed with, and it cannot be reissued for apps already in the store.
