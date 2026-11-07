# Cross Matrix

A Connect IQ watch face for the **Garmin Instinct Crossover AMOLED and Epix 2 family** — a
dot-matrix field where the data *is* the background. Four concentric rings of dots carry
their stats' colours and fill clockwise from twelve; the field saturates through the day
without restructuring itself. The Crossover's physical hands sweep above it. Epix watches
have no physical hands, so their outer ring tells the time.

## Quick start

```sh
make build                         # default Crossover simulator build
make build DEVICE=epix2            # build for another supported watch
make sim DEVICE=epix2              # launch the simulator and sideload
make install DEVICE=epix2          # push onto a USB-connected watch
make test DEVICE=epix2pro51mm      # run tests on the largest lattice
make package                       # signed multi-product Store package
make package-beta                  # the same, under the beta app id, for a Store beta
make sdk-info DEVICE=epix2         # show resolved SDK, device and key
```

## Prerequisites

| | |
|---|---|
| Java | 17+ (built and tested on OpenJDK 21, arm64) |
| Connect IQ SDK | 9.2.0 |
| Device files | The target IDs listed under *Supported devices* |
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

# 4. SDK + devices
connect-iq-sdk-manager sdk set 9.2.0
for target_device in instinctcrossoveramoled epix2 epix2pro42mm \
                     epix2pro47mm epix2pro51mm; do
  connect-iq-sdk-manager device download -d "$target_device" --include-fonts
done

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

## Supported devices

| Product IDs | Screen | Input | Hands | Dots |
|---|---:|---|---|---:|
| `instinctcrossoveramoled` | 390 × 390px | buttons | physical | 1,112 |
| `epix2pro42mm` | 390 × 390px | touch + buttons | time ring | 1,124 |
| `epix2`, `epix2pro47mm` | 416 × 416px | touch + buttons | time ring | 1,288 |
| `epix2pro51mm` | 454 × 454px | touch + buttons | time ring | 1,396, five rings |

With no hands to hide it, the Epix fills the hub with dots: its centre ring is a solid
disc rather than a ring round an empty middle, and its rings are measured from the centre so
the disc is no bigger than a ring is thick. The 51mm has a fifth ring, that centre disc,
showing Steps until set from the watch's own ring menu; every theme has a fifth colour for
it.

All targets are round AMOLED watches. Reference data lives under
`~/.Garmin/ConnectIQ/Devices/<product-id>/`; the SDK also provides a page under
`doc/docs/Device_Reference/<product-id>.html`.

**That memory figure is a runtime limit, and comparing a built `.prg` against it is a trap.**
`monkeyc` does not enforce it when building — a padded watchface `.prg` of 258KB compiles
fine. A debug `.prg` is much larger than its release equivalent because it retains symbol
tables rather than because it consumes that much watch-face memory. `Diagnostics` reports
actual runtime use as `used of total` on the settings screen; compare that value between
devices instead of comparing artifact sizes.

### Time hands

The Crossover has real hands over the display. The watch parks and sweeps them itself, but
their geometry matters and the simulator draws them. From its `simulator.json`:

| | |
|---|---|
| Hub (permanently covers the centre) | radius 21 px |
| Hour hand | 131 px reach, 28 px wide, white with black outline |
| Minute hand | 176 px reach, 28 px wide, **grey `0x808080`** with white outline |
| Default park | 270° / 90° — flat, revealing the face |

The grey minute hand is the one real constraint on the palette: mid-grey elements crossing
mid-grey dots would disappear.

The Epix family has no physical hands, so the outermost ring tells the time: two fills
clockwise from twelve, the hour's and the minute's, whose ends are where the hands would
point. Ring 1's setting picks the style, and offers nothing else:

- **Time: overlap** (the default) — each fill covers the whole ring: the hour blue, the
  minute red, purple where both have passed, grey where neither has. The colour sticking out
  past the purple is the one ahead.
- **Time: split** — the hour fills the ring's inner third and the minute its outer two, in
  white.

The ring stays lit in always-on and when the fills are held back, because it is the only
time display. There is no second hand — the optional seconds ring carries that reading
without forcing a redraw each second.

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

The cache now finishes in one synchronous `onLayout` pass. It computes one quadrant and
mirrors each result across both axes, so the expensive geometry runs once per four dots;
ring classification uses squared distances and angle uses the polynomial approximation.
The face therefore appears complete on its first frame, including in always-on mode where
updates may be a minute apart. `onStart` must still never build the lattice.

## Frame budget

A watch face gets a hard watchdog allowance per `onUpdate`, and this face draws ~1,100 dots
every frame in interpreted bytecode. Working out each dot's ring and position inside that
loop **tripped the watchdog outright** — `Code Executed Too Long`, thrown from
`StatMap.classify()`. The face would not load at all.

None of that work depends on the data — it is all geometry. So `DotGrid` computes it once
and caches parallel arrays of dx, dy, ring, position and cross orientation.
`MatrixRenderer` is then a flat walk with no calls in the inner loop, and `setColor` is only
issued when the colour actually differs.

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

**Each cross is turned to follow the circle it sits on** — one stroke pointing out from the
centre, the other across it, as near as a 5px cross can — `×` on the diagonals, tilting
one way then the other through each hour slot — which gives the field a radial grain matching the rings it is drawing. It is a setting (see
**Dot rotation**); upright, the field reads as a plain lattice with the rings drawn on it.

A cross has 90° rotational symmetry, and at 5px there are exactly four distinct ones: 0°,
26.6°, 45° and 63.4°. The turned field changes angle **on the hour marks** — each 30° hour
slot takes the cross nearest its centre, so it uses the three tilted ones and never the
upright — which puts every change inside an hour block's gutter. Each dot's
orientation is precomputed in `DotGrid` alongside its ring and position, so the loop just
indexes a table (`DotGrid.ARMS`). Arms are scaled so the larger component is always half a
dot, keeping every orientation the same visual weight; scaling by true length would make
the diagonals visibly shorter.

Strokes are drawn with `drawLine`, which **measured faster than the two `fillRectangle`
calls it replaced** — 33.5ms against 39.7ms a frame. Rotation cost nothing; it saved time.

The renderer only calls `setColor` when the colour actually changes. Runs of dots share a
colour, so with ~1,100 dots a frame this saves far more calls than it costs.

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
make install DEVICE=epix2    # build, check MTP mode, push
make push DEVICE=epix2       # build and push, skipping the checks
make reveal DEVICE=epix2     # manual fallback
```

The face goes onto the watch **directly, with no GUI and no drag**. `make
install` quits OpenMTP first if it is running — only one process may claim the
watch's USB interface at a time — and afterwards verifies the file against the
watch's own directory listing rather than trusting the transfer to have worked.
The first row under the face's on-watch settings shows the compiled version;
check it after a sideload to confirm the new PRG is the one currently running.

**These device generations are MTP-only.** Garmin moved away from USB mass storage,
so the watch never appears in `/Volumes`. The USB Mode prompt on the watch offers
two things, and neither is mass storage:

| Answer | What you get | Mountable? |
|---|---|---|
| **Yes, use MTP** | MTP — what you want; the USB product ID varies by model | No, but MTP clients can reach it |
| No | Garmin's proprietary protocol (`idProduct 0x0003`) | No, and it may not even charge |

The Crossover reports `0x5246` in MTP mode; an Epix Pro 51 mm reports `0x50DA`.
`make install` probes the MTP protocol instead of assuming one model's product ID.
Current firmware connects in MTP by default without asking; older firmware asks *Use
MTP?*, and the answer is **yes**. The first probe after plugging in can fail on its own,
so the installer retries once before saying the watch is not exposing MTP.
Then on the watch hold **MENU → Watch Face → Cross Matrix**. The
`.prg.debug.xml` beside the `.prg` stays on your Mac; it symbolicates crash logs
pulled from `GARMIN/Apps/LOGS/`.

### How the push works

macOS ships no usable MTP client, and **libmtp cannot talk to the Crossover used for
this trace**:
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

### Config code and the web configurator

**Settings → Config code** holds the whole configuration — every setting below plus a
custom theme — as one 38-character code. Paste a code there in Garmin Connect and the
face applies it; the field always shows the watch's current setup, so it can be copied
back out. `web/configurator/` builds codes in a browser, with a preview drawn on the
watch's own dot layout. It is published at **https://zolat.github.io/crossover-face/**,
rebuilt by `.github/workflows/configurator-pages.yml` whenever `main` changes it or the
settings it mirrors. To run it locally:

```sh
cd web/configurator && npm ci && npm run dev     # the configurator
make push-config CODE=<code>                      # apply a code on the simulator
make push-config TO=watch CODE=<code>             # write it to the watch on the cable
make web-test                                     # unit tests + a real-browser run
```

The format is `docs/config-code.md`. A sideloaded face gets no Garmin Connect settings,
so there the code goes over the cable: `make push-config TO=watch` writes it into the
face's settings file on the watch, and the face applies it when you unplug. The face must
be a build with config codes (`make install`) and must have saved a setting once — change
anything in its menu — so the watch has a settings file to write into.

### Colour theme

Which set of colours the rings carry. Every colour on the face comes from the theme's four —
the filled band, the dimmed field behind it, the mark, the second lap a ring runs past its
goal, and the temperature ramp.

| Theme | Ring 1 — outer | Ring 2 | Ring 3 | Ring 4 — inner |
|---|---|---|---|---|
| **Terrain** | orchid `#E879F9` | moss `#B8D64B` | ice `#7FD4FF` | rust `#FF6B5B` |
| **Activity** | red `#FE4646` | green `#6DC54F` | blue `#1F8FFE` | gold `#E59A0A` |
| **Beacon** | cyan `#5CD9F0` | red `#FE4646` | indigo `#8E7BFF` | gold `#E59A0A` |
| **Pulse** | red `#FE4646` | teal `#2FD9C5` | orchid `#E879F9` | lime `#B8D64B` |
| **Lemon & Azure** | lemon `#F0DC50` | azure `#3D9BFF` | lemon | azure |
| **Emerald & Violet** | emerald `#3FE08A` | violet `#B07CFF` | emerald | violet |
| **Orchid & Lime** | orchid `#E879F9` | lime `#B8D64B` | orchid | lime |

The last three are **duo-tones**: two colours alternating ring by ring, quieter under the
colour the data itself adds. Seven more live in the web configurator's extended library and
load as a custom theme.

**Activity** is not a palette invented for the face — it is the accent colours *this watch*
uses, the ones an activity profile picks from. They were read off the device's own artwork
rather than guessed: each `nwidget_*.png` and `D_list_select_*.png` in
`~/.Garmin/ConnectIQ/Devices/instinctcrossoveramoled/` is a ramp from black to one accent, so
the peak-chroma pixel *is* the accent, and the hue agrees to a tenth of a degree across both
sets of artwork.

Neither order is decorative. Neighbours blurring together, not the set average, decide whether
two rings can be told apart. Activity keeps gold, its one awkward colour, on ring 4: it has only
blue beside it and the innermost ring carries by far the fewest dots.

Gold got the same test that once rejected an amber for turning brown when dimmed: at the
unfilled tier it is `#7D5405`, a CIELAB chroma of 47.3, level with orchid's 47.0. All shipping
themes remain inside the 10% always-on luminance budget.

Beacon and Pulse graduated from the Colour Field Lab after visual review. Their persisted IDs
begin after the permanently retired `2–6` range, so an older stored setting can never silently
change meaning.

### Ring data

The face has four rings, and **each one is independently assigned to a source**:

| Source | Shape | Where it comes from |
|---|---|---|
| Steps | **goal** — level, then a second lap | `ActivityMonitor` steps ÷ your step goal |
| Battery | level | `System.getSystemStats()` |
| Body Battery | level | `SensorHistory` |
| Body Battery, last 12h | **blocks**, current + 11 counter-clockwise | `SensorHistory` current value + completed-hour averages |
| Temperature range | **range** + mark | `Weather` today's low → high, on a 0–60°C scale, with now marked |
| Chance of rain | level | `Weather.precipitationChance` |
| Rain, next 12h | **blocks**, clockwise | hourly `Weather.precipitationChance` |
| UV, next 12h | **blocks**, clockwise | hourly `Weather.uvIndex`, 0–10 |
| Temp, next 12h | **blocks**, clockwise | hourly `Weather` temperature, empty → full between two °C ends you set (default 0–45) |
| Intensity minutes | **goal** — level, then a second lap | `ActivityMonitor` weekly active minutes ÷ your weekly goal |
| Seconds | level, **awake only** | `System.getClockTime()`, filling through each minute |
| Off | — | nothing |

The four twelve-hour sources report **blocks**: twelve separated clock-hour slots whose
fill grows from the ring's inner edge outward. Rain, UV and temperature run clockwise into
the future; temperature fills linearly from *Temp ahead: empty at* to *full at*, both set
under Ring data on the watch or in Garmin Connect.
Body Battery puts its newest value in the current hour and completed-hour averages in the
eleven positions behind it, so reading backwards from the hand runs counter-clockwise. A
known zero uses the ordinary unfilled tier; an hour with no sample is dimmer and cannot be
mistaken for an actual zero. Block sources are available on the outer three rings, where
the lattice has enough dots to resolve them; ring 3 is the coarsest of the three.

Every other source reports a **span** — a start and an end, both 0.0–1.0 — rather than a
single level. Levels are just spans that start at zero. That one shape is why temperature,
which is a genuine range, needs no special case anywhere: a level fills from the origin, a
range floats between its ends and reads as an arc.

Temperature is the one source drawn on a ramp rather than a flat hue — cold through a middle
to hot, in the theme's own colours — so the ring reads as a temperature rather than just a
length. Terrain runs ice through orchid to rust; Activity blue through gold to red; Beacon cyan
through gold to red; Pulse teal through lime to red; and each duo-tone from its bluer colour to
its warmer one.

#### Past the goal — the second lap

Two sources are **goals** rather than bounded quantities: steps and intensity minutes. A goal
can be beaten, and both used to be capped at 100%, so the moment you hit your target the ring
stopped saying anything — 100% and 250% drew the identical full ring, and a full
intensity-minutes ring on Thursday lost the rest of the week.

Past the goal the overflow **runs a second lap**, which is exactly what the name says: the
ring fills clockwise from twelve, reaches twelve again, and keeps going round. It reads as
complete in its ordinary colour, and the arc the overflow has covered on its second time
round is drawn in a raised tier — so 134% is a full ring with its first third lightened. A
single filled dot marks the lap's **waterline**, the same shape as the temperature mark and
for the same reason: at 103% the raised arc is one dot long, and without the dot small
overflows are invisible.

The mechanism costs the render loop nothing, which is why it is done this way. A ring past its
goal is full by definition, so its *unfilled* tier has nothing left to describe: the span is
re-pointed at the overflow and the ring's two colours are swapped underneath the loop —
unfilled becomes "goal met", filled becomes "gone past it". Four assignments a frame, hoisted
out with the span ends and the ramp test. No dot ever learns that overflow exists.

Three edges are deliberate:

- **Exactly the goal is not over it.** The test is strictly greater. At `>=` a ring hitting
  100% would report a zero-length lap and drop a mark on the origin at the very moment the
  goal was met.
- **At double, the lap stops.** 200% and beyond draw one completed lap rather than starting a
  third, because carrying on round would report "only just started" at the moment of doing
  twice the goal — the ring would run backwards as the day went on. A lap that reached its end
  carries no dot: its waterline is the ring's own edge, so there is nothing left to point at.
- **It is awake only**, like the hand backing. Asleep a beaten goal reads as a
  plain full ring, which is true — it just stops saying by how much. Always-on is the mode
  measured against the burn-in budget, and every ring over goal costs 6.9% of screen luminance
  against 6.0% for every ring merely full.

The raised tier is the ring's own colour **mixed toward white**, not a brightening.
Brightening is not available: `Palette.LIFT` is 1.0 precisely because ice and orchid already
sit at a full channel, so scaling up clamps and shifts the hue rather than lightening it. The
tier sits about midway between the ring's colour and the mark's own tint, which leaves room on
both sides — clearly stronger than a ring that merely met its goal, and clearly dimmer than
the waterline dot that lands on top of it. `theOverTierReadsBrighterThanTheBand` holds that
order.

Nothing else overflows. Battery, Body Battery and both rain readings are bounded by what they
measure. Seconds is cyclic. Temperature is a range whose wrap past twelve is the design rather
than an overflow.

**Seconds is the one source that goes quiet.** It fills its ring from the origin and resets on
the minute — the leading edge of that fill is where a second hand would point — but only
while the watch is awake. Always-on is asked for one frame a minute, so a
per-second reading could only ever be stale there, and it is the mode the burn-in and
luminance rules are written against. Asleep the ring keeps its colour and shows no fill.

It is also the one source that costs something. The frame gate skips a frame whose fingerprint
matches the last one drawn, and a seconds span moves every tick, so with a seconds ring
assigned the face draws every awake second and the skip figure in **Frame cost** falls to
roughly nothing. That is the rate the face drew at before the gate existed, comfortably inside
the watchdog — but it is real battery, and it is the price of a second hand.

Its **0–60°C scale is deliberately far wider than any weather needs**: it puts one degree on
every minute mark, so the range can be read off the dial exactly the way you read the minute
hand. 18°C sits where :18 does. A tighter scale would use the ring better and be harder to
read.

A single pale dot marks **where the current temperature falls** in that range. Without it a
day of 11→22°C looks identical at dawn and at noon, and the reading is already in the
conditions the low and high come from. The mark outranks the fill, so it stays legible when
now sits *outside* today's range — an overnight low or a stale forecast puts it there
routinely, and drawing it where it actually falls is the honest answer.

It draws **in always-on too**, and goes only when the fills are held back. It used to be
awake only, alongside the hand backing, on the reasoning that a solid dot is the most
luminous thing per dot the face can draw. Priced rather than assumed, that does not hold: the
mark is one dot per ring, so even four rings on temperature move the always-on field by well
under a tenth of a point of screen against about four points of headroom, and the drift
carries it round the lattice like every other lit dot. What it buys is the reading — without
it a day of 11→22°C is the same picture at dawn and at noon, in the mode the face spends
nearly all its time in. `theAlwaysOnMarkFitsTheBudget` measures that on every theme.

The waterline dot on an over-goal ring is **still awake only**, and needs no rule of its own:
over-ness is awake-only at its source, so always-on never reports a lap to mark.

**It is one dot, not a row of them.** A row was tried first and does not work: drawn out of
crosses it reads as a bumpy dotted band rather than a line, and the dots inside the mark's
window span three degrees of angle on a square lattice, so a radial run of them staggers
instead of lining up. Nothing made of lattice dots can be a straight line at an
arbitrary angle. One dot cannot be crooked.

That dot is **filled, not a cross**. Every other dot on the face is two thin strokes, so a
white cross among eleven hundred of them is just another cross — it was tried, and at arm's
length it vanished. A solid block is the only shape on the field that is not a cross, and
that, rather than the colour, is what makes it read as a mark. It costs nine lit pixels
becoming twenty-five, once.

Which dot is decided by `DotGrid.markedDot()`: of the dots inside a window around the marked
position, the one nearest the mid radius of its ring, so the mark sits in the body of the
ring rather than trailing off at either edge. The window's half-width is **sized per ring**,
because a lattice row is 0.026 of a turn on the outermost ring but 0.076 of one on the
innermost; a single constant would fall clean between dots there and the mark would not be
drawn at all.

One consequence worth knowing: the mark snaps to a dot, so it carries up to about half a
degree of rounding — the dial has 38 rows across 60°C.

The scale **wraps rather than clamps**, which the minute-mark mapping implies: −5°C belongs
at :55, five degrees anticlockwise of twelve, exactly where minute 55 sits. Clamping instead
would fold every sub-zero reading onto twelve and quietly show a −5→3° day as 0→3° — a wrong
reading rather than a missing one. A frosty range therefore has its start *after* its end,
and `StatMap.isLit()` handles that case: a span whose end precedes its start wraps past the
origin. (−5°C and 55°C share a position; nothing confuses them in practice, and the scale
already wraps 60 onto 0 the same way.)

### Dot rotation

Follow the rings (default), or Upright. Turned, each cross points one stroke out from the
centre and lays the other across it, so the field carries the same radial grain the rings do.
Upright, every cross is the same `+` and the dots read as a plain lattice the rings are drawn
on.

It is **free either way**. Which way a cross would point is pure geometry, so `DotGrid` caches
it whatever the setting says and the renderer simply stops reading it — the setting never
touches the cache, and `rotationDoesNotReachTheCache` pins that. Upright is if anything the
cheaper frame, because the orientation lookup hoists out of the dot loop. Every orientation
lights the same nine pixels, so the luminance is identical: the mockup measures both at 4.82%.

### Date

On by default, on either rotation. The day of the month is drawn by joining the numeral's own
dots with faint lines, and only while the watch is awake: always-on shows the plain field, and
each wake draws the outline in. Watches that had `Upright + date` selected read it as `Upright` with the
date on.

`Date outline` sets how bright the connecting lines are: 50%, 65% (the default) or 80% of the
dots they join — the three levels the default was chosen between on the watch.

### Hands

Crossover only. `Off`, `White` or `Dark` backing dots beneath the physical hands, Off by
default and awake only. The Epix has no hands, so it neither shows nor reads the setting.

Two things make it work:

- On the Crossover, `View.setClockHandPosition({:clockState =>
  ANALOG_CLOCK_STATE_SYSTEM_TIME})` is called on wake so its hardware hands show the time
  rather than remaining parked.
- The footprint is the hands' own outline **exactly**, no wider — matching how Garmin's own
  faces do it. On the Crossover, what is lit sits *behind* the hand rather than in a wider
  corridor around it.
  The hands stand above the glass, so what you see is the lit area emerging along their
  edge. The mockups cannot show this: they draw the hands as flat opaque shapes with no
  gap, so the backing looks invisible there. Only the watch shows it properly.

Properties live in `resources/properties.xml`, are surfaced by
`resources/settings/settings.xml`, and are read by `Config.reload()`. Anything missing or
out of range falls back to its default rather than throwing — there are tests for that.

## Design tooling

```sh
python3 tools/mockup.py [outdir] [device]  # defaults: build/mockups, Crossover
```

Renders at the selected device's native resolution and composites into its Garmin artwork.
Physical hands are overlaid for the Crossover; the Epix sheets show the time ring (`14*`).
Device placement comes from the installed profile, while lattice and hand values mirror the
compile-time modules and are pinned by tests.

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
  data/BodyBatteryData.mc  current value and counter-clockwise 12h history
  data/HourlyWeatherData.mc  one hourly forecast sample for rain, UV and temperature
  matrix/DotGrid.mc   lattice geometry: pitch, circle clip, hub
  matrix/StatMap.mc   dot -> ring mapping and span test; the settings
  matrix/Drift.mc     burn-in mitigation cycle
  matrix/HandBacking.mc  which dots sit under the analogue hands
  data/Source.mc      what a ring can be assigned to; spans and hues
  data/WeatherData.mc today's temperature range and rain chance
  render/Config.mc    reloads settings and palette together
  settings/           on-device settings menu
  render/Palette.mc   four hues, two tiers, two power modes
  render/MatrixRenderer.mc  draws the field with a given palette
  render/TimeRing.mc  the Epix's time ring, in either style
  tests/              geometry, mapping and luminance-budget tests
resources/
  drawables/          launcher icon
  properties.xml      the settings' stored values
  settings/           how that setting is presented in Garmin Connect
  strings/            app name and setting labels
tools/
  mockup.py           design mockups, rendered into the device art
  luminance.py        always-on luminance budget measurement
  mtp_push.py         push the .prg to the watch over MTP, no GUI
source-lattice/       per-screen lattice and hand geometry
source-hands/         physical hands, or none and a time ring
resources-no-hands/   the Epix launcher icon
```

The signing key is deliberately outside the repo, and `.gitignore` covers `*.der` / `*.pem`
as a second line of defence. **Never commit it** — it is the identity your published apps
are signed with, and it cannot be reissued for apps already in the store.
