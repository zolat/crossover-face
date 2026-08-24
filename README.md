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

## Burn-in drift

The lattice walks a four-phase cycle, shifting ±3px and changing every two minutes
(`source/matrix/Drift.mc`). The numbers are forced by the geometry rather than chosen:

- Dots are 5px wide, so phases must differ by **at least 5px** or a pixel stays lit
  across the change. Opposite phases differ by 6px.
- The outermost dots sit 189px from centre on a screen 195px half-wide, leaving 4px of
  headroom after the 2px half-dot. **±3 is the largest amplitude that does not clip the rim.**

Drift is applied when drawing, never when deciding which dots exist, so the field
translates rigidly instead of popping dots in and out at the edge.

Measured over a full cycle by `tools/mockup.py`: **57,200 pixels touched, worst duty cycle
1 phase in 4.** No pixel is lit in more than one phase, so each rests 75% of the time and
is never lit for more than two minutes running. `make test` asserts the decorrelation and
the on-screen bound directly.

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

Current design, measured on-device by `make test`: **~4.6% active, ~2.0% always-on**, and
**~2.8% always-on at the worst case** of every stat reading 100%. `tools/mockup.py` agrees
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
- `HandBacking.MARGIN` widens the cleared area past the hands' own outline. The hands are
  opaque, so a backing cut to their exact shape is invisible — it hides underneath them.

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
  matrix/StatMap.mc   dot -> stat mapping; the layout seam
  matrix/Drift.mc     burn-in mitigation cycle
  matrix/HandBacking.mc  which dots sit under the analogue hands
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
