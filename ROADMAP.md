# Roadmap

**Current:** Epix 2 family support is integrated with UV ahead and Body Battery history,
including drawn dot hands and a touch-and-hold data peek. Temperature ahead has joined the
block sources since.

## Out-of-band features

- [x] Temp, next 12h — a block ring filled between two wearer-set °C ends (default 0–45),
  entered on the watch under Ring data or in Garmin Connect.
- [x] Date — its own setting, on by default: the numeral's dots joined by a faint outline,
  drawn in on every wake and absent in always-on. Replaces the struck watermark.
  - [x] Date outline — the line brightness as a setting: the 50 / 65 / 80% compared on the
    watch, 65 by default.
- [x] Always-on temperature mark — the current-temperature dot now draws asleep too, held
  back only with the fills.
- [x] Temp range + sun — the temperature range ring with today's sunrise (light yellow, outer
  edge) and sunset (blue, inner edge) as solid dots at their clock positions, from the
  watch's own Sunrise/Sunset complications. Mark and sun dots are now placed by `nearDot()`,
  a few-cell search that agrees with the ring walk, because three walks on one frame tripped
  the 416 watchdog.
  - [ ] Temperature range + drawn hands on the 454 Epix trips the watchdog — on `main` too,
    plain range included. Measured, not yet diagnosed.

## Epix 2 family

Out-of-band device work, not a phase of the performance roadmap that follows.

- [x] Phase 0 — download the four Epix profiles, confirm rather than assume
- [x] Phase 1 — put the screen behind a `Lattice` seam; crossover green through it
- [x] Phase 2 — the 454 lattice
- [x] Phase 3 — dot hands
- [x] Phase 4 — the other three products
- [x] Phase 5 — device-aware tooling

## What shipped

`manifest.xml` carries five products; `monkey.jungle` gives each one `Lattice` and one
`HandStyle`. The Crossover's picture is unchanged — same lattice, same single backing colour,
same suite green. The Epix draws its own hands out of the dot field, on by default, and keeps
them lit through always-on because there they are the only thing saying the time.

    screen  COLS  RADIUS  HUB  dots   devices
    390       38     190   21  1112   instinctcrossoveramoled, epix2pro42mm
    416       40     203   22  1272   epix2, epix2pro47mm
    454       42     210   23  1380   epix2pro51mm

129/129 on all five devices, simctl 44/44, five strict builds, and all eight package
variants.

## What was measured rather than assumed

- **Cross-module `const` still folds.** The seam's whole premise. Strict typecheck loses the
  *type* across it, so every constant carries `as Number` on both sides; the value folds
  fine, and the Crossover measuring 1112 dots through the seam is the proof.
- **Luminance is scale-invariant.** Dot density is `1/PITCH²` and each dot lights `2·DOT−1`,
  so the all-lit fraction is 8.8% at 390 and 9.0% at 454. No theme needed re-measuring.
- **Drawn hands cost 0.05-0.16 points**, worst theme 6.16% of the 10% cap, because they
  recolour lit dots rather than adding lit area. Solid polygons would have cost 5.03% at 390.
- **The per-dot hand test does not fit.** Eight float multiplies on 1544 dots tripped the
  watchdog and the face would not load; inlining it did not save it. The per-ring angular
  gate did.
- **The window has to open by `Angle.MAX_TURN_ERROR`.** The cached position is a polynomial
  approximation and the bar test is exact, so an exactly-sized window clips the hand by
  0.00027 of a turn. Found by the agreement test on its first run, not by eye.

## The post-merge frame A/B

Measured on the same machine and simulator profile, alternating current `main` and the
integrated branch in isolated instances:

    row                         current main           integrated
    defaults                    18ms avg / 22 worst    19ms avg / 23 worst
    hand backing                22ms avg / 27 worst    20ms avg / 23 worst
    hands + seconds + temp      watchdog trip           6ms avg / 20 worst
    memory                      61k of 123k             64-66k of 123k

The integrated busy row skipped 0% of frames and remained alive. Reading the clock once per
frame and replacing temporary ring-window arrays with scalar bounds also fixes that
current-main worst-case crash. On Epix, the expensive combination is separated by design:
drawn hands show the time, while touch-and-hold hides them and reveals the upright date.

## Left on the table

- **The 454 lattice is one step short of native.** `COLS 44` — 1512 dots, a 12px rim
  matching the Crossover's own 10px — trips the watchdog with the hands on. Bisected: 1388
  runs, 1444 does not. 1380 ships, at a 22px rim. The lever is `PITCH`, which drags `DOT`,
  `DotGrid.ARMS`, `Drift`'s offsets and the Python mirror with it — a phase, not an edit.
- **Dark hands were chosen on the mockups, not on hardware.** Rendered at six times of day,
  a bright hand is more of what is already there and genuinely hard to find among ~1400 lit
  crosses; cut out of the field it is the only dark shape on a lit disc and reads at a
  glance. It holds awake, in always-on and held back, and costs less light in all three
  (4.12% against 4.50% awake). White is still a setting away. Widening the hands from 30px
  to 44px was measured too — 4.55% white-and-grey — and was not taken, because dark solved
  the legibility problem without touching the geometry.
- **Nothing has run on a real Epix.** Everything here is the simulator, including the
  watchdog trips — which the simulator enforces from the device profile's own count, so they
  should be real, but the frame budget deserves a check on the wrist.
- **`simctl.settings` labels do not follow the per-device string override.** It reads the
  base `resources/strings/strings.xml`, so an Epix build's `handBacking` prints the
  Crossover's wording. Cosmetic, in a tool, and not worth reimplementing resource resolution
  in Python for.
- **The Epix face crop is a percent or two out.** Good enough to see the face by, not good
  enough to measure; `MatrixTest` is the luminance authority anyway.
- **A continuous-arc face is a separate experiment.** This release keeps the established
  lattice and dot language; an arc renderer should be evaluated independently.

# Previously: Rain, next 12h (complete)

**Current:** done — Rain, next 12h shipped; the frame A/B and the on-watch check are below.

Out-of-band feature work, not a phase of the performance roadmap that follows: that one is
complete and this does not extend it.

- [x] Rain, next 12h — an hourly forecast in one ring
- [x] Block levels — width as the second axis, so a block reads sixteen ways rather than four
- [x] Block centring — a block sits between its two hour marks, not against the first one
- [x] Date watermark — the day of the month written into the grain of the dot field
- [x] UV, next 12h — the hourly UV index clockwise ahead of the hand
- [x] Body Battery, last 12h — current live, completed hours averaged counter-clockwise

Plans: `~/.claude/plans/i-want-to-plan-starry-graham.md`,
`~/.claude/plans/encapsulated-finding-owl.md`,
`~/.claude/plans/could-we-subtely-wite-curried-forest.md`

## The date outline, and what the wrist settled

The struck watermark below shipped and was **invisible on the wrist**: the mockups said it
read, and on the watch a 5-against-9-pixel density step was lost in a window whose rings
change colour and tier under it. The lab that replaced it (`date-dot-lab` branch,
`tools/date_lab.py`, `fill_lab.py`, `contour_lab.py`, `reveal_lab.py`) tried, in order:

| idea | verdict |
|---|---|
| aligned dashes, long dashes, pinpricks, dimming, nudges, threads | read in mockups; subtle ones still faint |
| solid fill in the ring colour | reads instantly; +4.8 points, over budget in always-on |
| outline along cell edges | fights the grid |
| **outline through the dot centres, crosses kept** | **chosen** |
| line at 100% / 40% / 50 · 65 · 80 a minute apart on the watch | too obvious / vanished / **65** |
| pinprick reveal on BACK | BACK reaches the face through no callback at all — counters never moved |

Settled on the watch, not the monitor: always-on shows no date (a line overlaps itself under
the drift: 1,872 pixels at 2-of-4 duty against 1-of-4 for every dot), every wake draws the
outline in, and the lines fill only the gaps between arms so the crosses stay whole. The
date became its own setting so it can ride either rotation; on the turned field its joins
float between diagonal crosses, which the wearer accepted over forcing the field upright.

The trace tripped the watchdog in the simulator when it ran inside onUpdate on top of a new
day's full redraw, so it runs from the wake, show and peek callbacks instead.

**The frame A/B**, Crossover, Follow the rings, medians over ~70 frames with the first three
dropped. Each leg was its own binary with its settings baked into `properties.xml`, on its
own fresh simulator instance, run back to back. Running averages were useless here: every
leg's first frame fills the frame buffer at 1–5s in the simulator, and on the defaults row it
is nearly the only drawn frame there is.

    row (frame kind)            main         branch, date off   branch, date on
    defaults (skipped)          15ms / 23    15ms / 23          13ms / 21
    seconds + temp (drawn)      47ms / 61    43ms / 56          55ms / 83
    454 Epix, hands off, busy                                   28ms / 32, no trip

    first cut, inking every segment on every drawn frame:       186ms / 227

The new comparison per dot on the turned field does not show. The date's own cost on a
drawn frame was the outline: ~90 native `fillRectangle` calls at ~0.4ms each in this
simulator, 37ms a frame, re-inked whether anything under it had moved or not. Only a clear
touches the gaps the outline lives in, so each segment now remembers the colour it stands in
and only a changed dot's segments, or a clear, re-ink it — 0–2ms a frame, and
`theOutlineReinksOnlyWhatChanged` holds it. What is left, ~10ms median and a heavier tail, is
the periodic clear that re-inks everything.

Two harness facts the run cost, worth keeping: a fresh simulator instance takes its settings
from `properties.xml` on the first push, so a settings write before it is lost; and a second
push of an identical `.prg` into an instance never registers as landed, so a sweep needs one
instance per leg.

## The date watermark, and what the mockups settled

The ask was to write the date into the field by **rotating** dots — turning a chosen few
45 degrees so a numeral appears in the grain rather than on top of it. Orientation is the
one channel this face has that costs no light: every cross lights nine pixels whichever way
it points.

**Rotation is free and does not read.** Measured in `tools/mockup.py`, a face with a rotated
numeral in it and one without measure the same 4.821% — identical to every digit. But at a
five-pixel dot a `+` and a `×` are too close to tell apart, and at a 3x5 font the numeral is
a faint sheen at 1:1 and nothing at all on the wrist. The face has form here: the
temperature mark had to become a solid block because "a white cross among them is just
another cross — it was tried and it vanished".

**What reads is density, not orientation.** A *struck* dot draws one of its two strokes and
not the other — five lit pixels instead of nine, same cell, same colour. Four markings were
rendered at 1:1 and at wrist scale:

| marking | luminance | reads as a number? |
|---|---|---|
| none | 4.82% | — |
| rotate 45°, 3x5 font | 4.82% | no — a faint texture patch |
| rotate 45°, double-size font | 4.82% | faintly, at close range |
| **half-weight stroke, double-size** | **4.64%** | **yes** |

**And it is free in the safe direction.** A struck dot lights a strict subset of the pixels
it lit before, so the frame total can only fall — no luminance bound needed re-measuring,
and the argument is arithmetic rather than a measurement.
`strikingADotOnlyRemovesLight` asserts the premise it rests on.

**Double-size, because a one-dot stroke is not a stroke.** A 3x5 digit at one lattice cell
to the font pixel is 30x50px, which sounds ample; its strokes are one dot wide and have no
coherent area to read as strokes. At two cells they are 20px wide and the numeral is there.
The window is 14x10 cells, horizontally centred, in the lower half — the only placement of
that size that clears the hand pivot, and all 140 of its cells hold a dot.

**The frame cost is below this machine's noise floor, and saying so took twelve legs.**
One integer comparison per dot is per-dot work, which CLAUDE.md requires re-measuring both
rows for. Two builds — a `const` reproducing the loop with no comparison in it at all,
which is the only honest "before" — interleaved back to back, two rounds:

| rings | leg | round 0 | round 1 |
|---|---|---|---|
| defaults | A pre-watermark loop | 29ms / 46 worst | 40ms / 73 |
| | B watermark off | 37ms / 83 | 35ms / 56 |
| | C watermark on | 34ms / 66 | 34ms / 64 |
| seconds + temperature | A pre-watermark loop | 11ms / 56 | 14ms / 84 |
| | B watermark off | 12ms / 66 | 13ms / 71 |
| | C watermark on | 13ms / 74 | 14ms / 81 |

**Read the defaults row as the null result it is.** A→C reverses direction between the two
rounds — C is 3ms *below* B in round 0 and A is 6ms above C in round 1 — which cannot be a
cost of the comparison and is the machine moving under the measurement. The seconds row,
where nothing is ever skipped and the sample is therefore steadier, is monotone and tiny:
+1ms for the comparison, +1ms more for the strike. Idle is unmoved at 0-1ms in every leg,
so `DateGlyph.today()`'s day-key arithmetic does not show up on a skipped frame.

What *is* consistently measurable is memory: **61k to 63k**, in every leg the watermark was
on, for the two ≤140-entry tables. Against 123k granted.

Three things about the mechanism are load-bearing:

- **The struck dots are named by index, in the order the renderer walks them**, so
  membership costs one integer comparison per dot rather than a lookup. The lattice scan
  that finds them runs in index order, which is why the list comes out sorted with no sort
  and no reverse map.
- **The cursor advances in the branch that consumed it**, not at the top of the loop — one
  comparison for an ordinary dot instead of a test and a local. That only works because
  the delta redraw is told never to skip a struck dot (`i != glyphNext`), or a skipped dot
  would leave the cursor a step behind and shift the whole numeral along the ring.
- **The day is in the *field* print**, so midnight clears the screen. A dot struck yesterday
  and not today has four pixels a repaint cannot remove — the repaint draws the cross's
  other stroke, which is exactly those four.

## What it is

A ring's 360 degrees become twelve 30-degree hour slots, one per hour ahead. A 22.5-degree
block in each leaves a countable gutter. How far a block reaches out through the ring's own
42px thickness is the chance of rain — and then how far it spreads *across* the block's own
width. A block holds a level from 0 to 15: the whole part of `L * BANDS / LEVELS` is that
many full-width sub-bands, the remainder is the angular half-width of the next band out,
centred in the block. An hour the forecast said nothing about draws a fourth tier at 0.25,
darker than the 0.55 unfilled one, so "no data" cannot read as "forecast says dry".

## What the measurements settled

**Three sub-bands, not four.** A ring is 42px, so a four-way split is 10.5px bands beating
against the 10px lattice pitch. Dots per block per sub-band:

| ring | 3-way | 4-way |
|---|---|---|
| 0 (outer, 436 dots) | 11.0 / 12.3 / 13.0 | 8.3 / 9.7 / 9.7 / 8.7 |
| 1 (340 dots) | 8.3 / 9.0 / 11.0 | 7.0 / 5.7 / 9.0 / 6.7 |

Four is clean on ring 0 and lumpy on ring 1. The source must work on either, so three wins.

**The outer two rings only, and that is a lattice fact rather than taste.** The worst
(block, sub-band) holds 8 dots on ring 0 and 6 on ring 1, against 4 on ring 2 and 2 on ring
3. `onlyTheOuterTwoRingsResolveTwelveHoursInThreeBands` asserts it, so if the lattice ever
changes the test says whether `Source.BLOCKS_TOP_RING` still means what it claims. The
level scale sharpens this only on the innermost ring, where sixteen (block, level) pairs
light no dot at all — ring 2 draws every rung, so its exclusion still rests on the dot count
and on nothing else.

**Width is worth eleven readings an hour, and it is free.** The three sub-bands cap the
radial axis; the angular one was untouched, with every lit band drawn full width across 8-13
dots. Level 15 is exactly the three full bands the old top tier drew, so nothing the widened
scale can draw was already impossible and **no luminance bound needed re-measuring**. Dots
lit in the worst block, per level:

| ring | level 1 | 5 | 10 | 15 |
|---|---|---|---|---|
| 0 (outer) | 2 | 8 | 17 | 27 |
| 1 | 1 | 6 | 13 | 20 |

**No minimum window, and that was measured rather than assumed.** The obvious worry is that
a level-1 window — a fifth of one sub-band — falls clean between two dots of a square
lattice, so the bottom of the scale draws nothing and 10% is indistinguishable from the dry
hour it used to be. On the offered rings the geometry already delivers it, monotonically;
`everyNonZeroLevelLightsAtLeastOneDot` and `aLevelIsMonotonicInDotsLit` hold it there. A
floor sized off `DotGrid.markerHalf` is the fix if that ever changes, not a coarser scale.

**The block loop costs 2.7ms more.** 87.3/87.8/87.8ms against 85.9/84.3/85.4 for the old
whole-band fill, on ring 0's 436 dots at the worst level, A/B'd out of one binary under one
load. The span loop is byte-for-byte unchanged, so no other ring moved.

**The hour-hand anchoring costs nothing.** The hand at local hour H points at clock position
H mod 12, so the forecast N hours out belongs at (H + N) mod 12 — which is that forecast
hour's own hour-of-day, mod 12. Bucket by the entry's own local hour and it lands where the
hand will be. There is no rotation step on either side, and the plan's estimate of one was
the largest thing this turned out not to need.

## The frame A/B, and what it did and did not settle

CLAUDE.md's rule is that adding per-dot work means re-measuring both rows, and this added
some to the Crossover's hot loop. Measured same-session, same machine, merge base against
this branch, one isolated simulator per leg and the legs alternated — two binaries with one
PRG stem cannot share an instance, because `load()` decides a push has landed by that file's
mtime and swapping them under one name never moves it.

    row                    base                    branch
    defaults, hands off    21ms / 27  80% skipped  20ms / 29  80% skipped
    defaults, hands ON     80ms / 101 80% skipped  79ms / 102 80% skipped
                          101ms / 159 76% skipped  96ms / 113 80% skipped
    seconds + temp         (leg invalid)           24-27ms / 93-111  0% skipped
    memory                 57k of 123k             59k of 123k

**No regression on the row that changed most.** Hands ON is where the gate replaced the bar
test, and it comes out level or slightly ahead on the worst frame. The +2k of memory is the
two new per-*ring* arrays and HandStyle; nothing per-dot was added to the cache.

Two caveats, both real:

- **the machine drifted between samples.** A leg's two samples differ by up to 4x in the
  hands-off row, which is load rather than code — exactly the trap CLAUDE.md warns about.
  The paired samples within a row are what to read, not any figure against another day's.
- **the seconds + temperature row never got a valid base leg.** The base binary was called
  `base.prg`, and simctl derives the settings filename from the PRG *stem*, so it wrote
  `BASE.SET` and the base leg quietly reported default rings for every row. Fixed by renaming
  the binary, but the rerun ran into a slept display and was abandoned rather than reported
  half-measured. The branch's own figure for that row, 24-27ms at 0% skipped, is the same
  class as the 31ms / 97 worst on record.

## Left on the table

- ~~**Nothing has been seen.**~~ Settled: the face has now been screenshotted awake with a
  graded forecast on the outer ring, and the lit pixels per block were counted off the
  capture — 0% and 5% dark, 10% a two-dot pip, monotone round to 100%, the unforecast hour
  on the dim tier. The earlier *could not create image from window* was the Mac display
  asleep, not a missing permission; `caffeinate -u` wakes it, `-d` only stops it sleeping
  again. It needed a temporary stub for the forecast and a forced ring assignment, so the
  *data path* from `Weather` is still unexercised — see the last bullet.
- ~~**The gutter's alignment is unexamined.**~~ Settled by looking at it on the wrist, which
  is what this item asked for. Leading alignment put every block 3.75 degrees anticlockwise of
  its slot's centre — about 12px of arc on the outer ring, and plainly visible against the
  printed dial. Blocks are now centred: the gutter is split 3.75 degrees either side of each
  hour mark, and the hand is inside its own block from :07.5 to :52.5 rather than leaving
  early at :45. Measured before and after off simulator captures of the same stubbed
  forecast: **aggregate lit centroid 11.57 -> 15.46 degrees** into a 30-degree slot, against a
  15.00 target, the residual being hand occlusion. Centring the block also made every rung
  above level 1 more even, and ring 1's full block a flat 21 dots across all twelve; the cost
  is level 1 drawing 1 dot at four hours and 3 at the rest, where a floor to even it up would
  collapse it into level 2. Costs about 1ms a drawn block ring, inside run-to-run spread.
- **On-watch verification.** `getHourlyForecast()` returns null in the simulator, so every
  hour is unknown there and the whole ring draws the dim tier. Nothing has exercised the
  bucketing against a real forecast, and the array's length is undocumented — the dim tier
  exists precisely because it may come back shorter than twelve.

# Previously: the frame budget (complete)

**Current:** superseded by Phase 7. Phase 6 made transitions instant on the
physical watch, but its inferred two-buffer lifecycle produced flashlight
animation ghosts and intermittent black frames.

- [x] Phase 0 — baseline the frame cost on a fresh simulator
- [x] Phase 1a — cost the skipped frame, which nothing measured before
- [~] Phase 1b-1e — dropped on the measurement; see below
- [x] Phase 2a — memoise DotGrid.markedDot()
- [x] Phase 3 — redraw only the rings that changed
- [~] Phase 2b — dot-loop micro-hoists; not taken, see below
- [x] Phase 4 — cost the off-screen mirror, the palette swap, and the native
      draw, so the next optimisation is chosen on numbers rather than on the
      claim in a comment
- [x] Phase 5 — draw only the dots that changed, not the whole ring
- [x] Phase 6 — make view and power-mode transition bursts draw once, then skip
- [~] Phase 7 — rejected on the physical watch: an unchanged layer was not
      recomposited during native transitions
- [~] Phase 8 — explicitly present a cached complete bitmap on every callback;
      simulator-complete, physical-watch verification pending

Plans: `~/.claude/plans/can-you-review-for-stateless-puffin.md`,
`~/.claude/plans/are-there-any-more-staged-piglet.md`

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

1d is now complete. The two prints are preallocated and `FrameGate.copy()` keeps
values rather than the caller's array — not for the microsecond, but because the gate
storing a reference to a buffer the view refills would compare an array with itself and
freeze the face to one draw per cap. The spans, blocks, overflow flags, markers, drift,
hand axes and renderer mark scratch are now caller-owned buffers too, so an ordinary
update creates none of those short-lived arrays.

**Phase 2b is not taken.** Splitting the dot loop on `turned` duplicates the loop body, and
the loop now runs on one ring in five frames out of six rather than on four rings every
frame. The cost it addresses shrank by more than the change would save.

## The frame A/B, and what it did and did not settle

CLAUDE.md's rule is that adding per-dot work means re-measuring both rows, and this added
some to the Crossover's hot loop. Measured same-session, same machine, merge base against
this branch, one isolated simulator per leg and the legs alternated — two binaries with one
PRG stem cannot share an instance, because `load()` decides a push has landed by that file's
mtime and swapping them under one name never moves it.

    row                    base                    branch
    defaults, hands off    21ms / 27  80% skipped  20ms / 29  80% skipped
    defaults, hands ON     80ms / 101 80% skipped  79ms / 102 80% skipped
                          101ms / 159 76% skipped  96ms / 113 80% skipped
    seconds + temp         (leg invalid)           24-27ms / 93-111  0% skipped
    memory                 57k of 123k             59k of 123k

**No regression on the row that changed most.** Hands ON is where the gate replaced the bar
test, and it comes out level or slightly ahead on the worst frame. The +2k of memory is the
two new per-*ring* arrays and HandStyle; nothing per-dot was added to the cache.

Two caveats, both real:

- **the machine drifted between samples.** A leg's two samples differ by up to 4x in the
  hands-off row, which is load rather than code — exactly the trap CLAUDE.md warns about.
  The paired samples within a row are what to read, not any figure against another day's.
- **the seconds + temperature row never got a valid base leg.** The base binary was called
  `base.prg`, and simctl derives the settings filename from the PRG *stem*, so it wrote
  `BASE.SET` and the base leg quietly reported default rings for every row. Fixed by renaming
  the binary, but the rerun ran into a slept display and was abandoned rather than reported
  half-measured. The branch's own figure for that row, 24-27ms at 0% skipped, is the same
  class as the 31ms / 97 worst on record.

## Left on the table

- ~~**The repair cadence is the remaining lever.**~~ Taken in Phase 6: `MAX_SKIPS = 30`.
  A normal wrist raise now ends before its periodic repair, while power-mode changes force
  one valid complete frame, onShow repairs both buffers after system overlays, and
  low-power still paints one complete frame per actual minute.
- **The hand-backing coverage bitset**, worth ~4ms of a full redraw but only with backing
  on, which this configuration does not use.
- **Compiled weak-field background spike.** Distinct from Phase 4's runtime mirror: a
  palette-indexed resource would avoid populating the buffer and could replace the weak
  dots in a full frame with one blit, leaving the existing delta path for changed dots.
  Defer until physical-watch testing says the one remaining complete transition frame is
  itself visible; the simulator's ~20ms blit floor can otherwise make it a regression.
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

---

# Phase 4: what the remaining radical levers actually cost (complete)

**Current:** done — delta redraw is the recommendation; the off-screen mirror is dead.

The question was whether anything *radical* was left after the per-ring gate, and two
candidates could not be settled by reasoning: an off-screen mirror the field is rendered
into and blitted from, and a palette-indexed buffer whose colours are swapped per frame
instead of its pixels being redrawn. Both turn on numbers nobody here had measured.

## Method

Five legs, chosen **per drawn frame out of one binary**, so every leg saw identical load:

    A  MatrixRenderer.draw to the screen Dc, untouched      the baseline
    B  the same loop with the two drawLine calls deleted    native vs bytecode
    C  the renderer into a mirror's Dc, then one blit       the mirror path
    D  the blit alone, no field walk                        the repair frame, mirrored
    E  setPalette on a paletted buffer, then one blit       the palette swap

The leg is picked from an LCG rather than `frame % 4`. Round-robin would have shared a
factor with `MAX_SKIPS = 5`: with a seconds ring every tick draws and the repair lands
every sixth frame, so `gcd(6, 4) = 2` would have put every expensive clear-and-redraw on
two legs and none on the others, inflating `A - B` — the one number the exercise exists
to produce.

Costs are **stratified by frame class**, partial against repair, never blended, for the
same reason `Diagnostics` already keeps drawn and idle apart. Leg B is a spike-only clone
of the loop rather than a flag inside it: a per-dot `if` would have added ~1100 compares
to leg A and corrupted the baseline.

Simulator only. The watch leg was cut: legs B, D and E draw a deliberately wrong frame, so
the build is not a usable face and has no business on a wrist — see *Left on the table*.

## The numbers

Milliseconds, average over the sample count shown. `p` is a partial frame, `r` a repair.

| leg | seconds + temperature | defaults |
|---|---|---|
| A  baseline               | **36** / 129p, **87** / 31r | — / 0p, **72** / 32r |
| B  no drawLine            | 15 / 129p, 40 / 32r         | — / 0p, 32 / 30r     |
| C  draw into mirror, blit | 22688 / 126p, 4288 / 30r    | — / 0p, 3527 / 31r   |
| D  blit only              | 21 / 150p, 23 / 38r         | — / 0p, 18 / 35r     |
| E  setPalette, blit       | 23 / 143p, 21 / 32r         | — / 0p, 19 / 34r     |

The defaults column has **no partial frames at all**, which is not a gap in the sampling:
at default rings the gate skips ~80% of frames and `sinceClear` counts skips, so nearly
every draw there is the periodic repair. `FrameGate`'s own comment said as much; this is
the measurement of it.

## What it settles

**Native drawing is ~55% of a drawn frame, consistently.** `B/A` is 42% on a partial
frame, 46% on a seconds repair, 44% on a defaults repair — so the two `drawLine` calls per
dot are 54-58% of the cost and the interpreted loop is the rest. That is the number that
sizes delta redraw, and it is the largest single lever left.

**The off-screen mirror is dead, on two independent counts.** Populating it cost 22.7
*seconds* on a partial frame — 600x the baseline, and worse than its own repair frame,
which is a red flag rather than a cost model: a partial frame draws one ring, so it cannot
honestly cost five times a frame that draws four. Three artifacts were found and removed
before that number and it did not come down (below). But the mirror does not need leg C to
fail: **leg D alone kills it.** Presenting the buffer costs ~20ms, and a whole partial
redraw costs 36ms. Even with population free, a mirror would trade 36ms of drawing for
20ms of blitting on the frame that matters most, while adding a 304KB dependency.

**`setPalette` is nearly free, and is the only radical option still standing.** Leg E
matches leg D within noise, so swapping 128 palette entries costs ~0-2ms on top of the
blit. Its per-frame cost is ~20ms *flat*, whatever changed — no dot loop at all. That is
worse than a partial frame today (36ms would become 20ms, a real but modest win) and much
better than a repair (87ms to 20ms). It is not free of consequences: encoding each dot's
(ring, position) as a palette index quantises the fill edge to ~60 buckets a ring, which
is a visible change to how the seconds ring advances, and that is a design decision rather
than a performance one.

**The memory claim in `CLAUDE.md` was wrong, though its conclusion survives.** All four
buffer sizes allocated — 390x390 at 16bpp (~304KB) included — and the app heap moved by
**616 bytes**, because `createBufferedBitmap` allocates from the graphics pool, which the
SDK documents as separate from the application heap since API 4.0. The ladder, every rung
`ok`, heap delta in bytes: 16bpp 616, 8bpp 616, 8bpp+palette 1280, 4bpp+palette 720. So
the field *can* be cached to a `BufferedBitmap`; it simply should not be. Unverified on
the watch.

## Where this departs from the rule written before the numbers

The plan pre-registered a decision rule so the result could not be argued with afterwards,
and one branch of it fired: *"allocation succeeds and `D` is materially below **A-repair**
→ the mirror is the next phase."* Allocation succeeded, and `D` is 23ms against
`A-repair`'s 87ms. By the letter of the rule the mirror wins.

It is still rejected, for a reason the rule did not anticipate: it was written expecting
leg C to produce a number, and leg C came back unmeasurable rather than merely large. With
population uncosted, all that survives is `D` — and `D` is a **floor**, ~20ms on every
drawn frame whatever changed. Delta redraw's estimated ~16ms on a partial frame sits
underneath that floor, and partial frames are the class that dominates the configuration
the face is actually judged on. A rule keyed on the repair frame missed that the two
options are not competing for the same frame.

Recording the deviation rather than quietly re-reading the rule, because the point of
writing it down first was to make exactly this visible.

## Three artifacts, and one API fact worth keeping

Each of these was a wrong number before it was a finding, and leg C would have been
reported as 5200ms, then 1171ms, then 22688ms depending on when we stopped looking.

- **The pool purges a buffer whose object you do not hold.** `createBufferedBitmap` returns
  a *reference*; the SDK allocates in `get()` and locks the resource only while the object
  it returns is in scope. Taking `get()` per frame and letting the result fall out of scope
  measured ~5200ms a frame — the pool reloading 304KB every frame. Pinning the
  `BufferedBitmap` in a variable cut it to ~880ms.
- **`getDc()` per frame is allocation pressure**, not drawing. Caching the Dc removed a
  drift where leg C's average *grew* 387ms to 1171ms across eight frames rather than
  settling.
- **A leg that is off must cost no frames**, not be folded into another leg, or the
  remaining legs quietly change their share of the repair cadence.
- **`dc.setAntiAlias(false)` throws on a paletted buffer** — *"Anti aliased primitives
  cannot be drawn to a paletted buffer"* — and `dc has :setAntiAlias` still answers `true`,
  so the guard already in `MatrixRenderer` does not catch it. It crashed the face on leg
  C's first frame. Harmless in principle, since a paletted buffer has no anti-aliasing to
  turn off and off is what the face wants; but any paletted-buffer design has to stop
  making that call, which means touching the renderer.

## Recommended next, in order

1. **Delta redraw.** Redraw only the dots whose lit-ness changed since the last draw
   rather than all ~280 in a dirty ring. Needs no new API, no new memory and no visual
   change; `FrameGate._rings` already holds the previous span, which is exactly the input.
   The ~280-dot compare scan stays (leg B, 15ms) and the drawing collapses to ~10 dots, so
   a 36ms partial frame should land near 16ms. The `HOLD = 2` double-buffer rule still
   applies: paint the union of the last two deltas, mirroring what `drawnMark` and
   `previousMark` already do for the mark.
2. **The hand-backing coverage cache**, still worth ~4ms and still backing-on only.
3. **`setPalette`**, only if the fill-edge quantisation is acceptable as a design change.
4. **Not the mirror.**

## The frame A/B, and what it did and did not settle

CLAUDE.md's rule is that adding per-dot work means re-measuring both rows, and this added
some to the Crossover's hot loop. Measured same-session, same machine, merge base against
this branch, one isolated simulator per leg and the legs alternated — two binaries with one
PRG stem cannot share an instance, because `load()` decides a push has landed by that file's
mtime and swapping them under one name never moves it.

    row                    base                    branch
    defaults, hands off    21ms / 27  80% skipped  20ms / 29  80% skipped
    defaults, hands ON     80ms / 101 80% skipped  79ms / 102 80% skipped
                          101ms / 159 76% skipped  96ms / 113 80% skipped
    seconds + temp         (leg invalid)           24-27ms / 93-111  0% skipped
    memory                 57k of 123k             59k of 123k

**No regression on the row that changed most.** Hands ON is where the gate replaced the bar
test, and it comes out level or slightly ahead on the worst frame. The +2k of memory is the
two new per-*ring* arrays and HandStyle; nothing per-dot was added to the cache.

Two caveats, both real:

- **the machine drifted between samples.** A leg's two samples differ by up to 4x in the
  hands-off row, which is load rather than code — exactly the trap CLAUDE.md warns about.
  The paired samples within a row are what to read, not any figure against another day's.
- **the seconds + temperature row never got a valid base leg.** The base binary was called
  `base.prg`, and simctl derives the settings filename from the PRG *stem*, so it wrote
  `BASE.SET` and the base leg quietly reported default rings for every row. Fixed by renaming
  the binary, but the rerun ran into a slept display and was abandoned rather than reported
  half-measured. The branch's own figure for that row, 24-27ms at 0% skipped, is the same
  class as the 31ms / 97 worst on record.

## Left on the table

- **Nothing here is confirmed on the watch.** The spike build cannot be worn — three of
  its five legs draw a deliberately wrong frame — and the watch has no way to report a
  number back: `println` reaches the simulator only, `CIQ_LOG` is written on a fault only,
  and `tools/mtp_push.py` can upload but not download. An on-watch A/B needs a build whose
  legs are all *correct* renderings, compared across runs rather than within one, which
  gives up the same-load property the CLAUDE.md protocol demands. That tension is
  unresolved and is the main reason these figures are ratios rather than absolutes.
- **Leg C is not a cost model.** It says the simulator cannot draw into a BufferedBitmap at
  a sane speed, not that the watch cannot. The recommendation does not rest on it — leg D
  is what rules the mirror out — but if a mirror is ever revisited, leg C has to be
  re-measured somewhere real.
- **The simulator's `.SET` store is per app name.** `CROSSOVERFACE.SET` and
  `CROSSOVERFACE-TEST.SET` are separate files here, so settings written for one do not
  reach the other, and a run kept coming up on the defaults however the file was written.
  `CLAUDE.md` says the face and the test build share one file; that is not what this
  checkout does, and the spike pinned the ring assignment in the build to sidestep it.

---

# Phase 5: draw only the dots that changed (complete)

**Current:** done — 7ms against 24ms on the frame class that dominates.

Phase 4's one actionable number was that the two `drawLine` calls per dot are ~55% of a
drawn frame. A dirty ring repainted all ~280 of its dots; between one draw and the next a
seconds ring moves its edge about five. So the ring is still *walked* — the compare scan is
the cheap half — and only the dots whose lit-ness changed are drawn.

## The numbers

Same-load A/B out of one binary, leg picked per drawn frame, seconds + temperature:

| frame | delta redraw | whole ring |
|---|---|---|
| partial | **7ms**, 20 dots, n=134 | 24ms, 436 dots, n=112 |
| repair  | 67ms, 1112 dots, n=30  | 65ms, 1112 dots, n=23 |

The repair legs run **identical code** — a delta is ruled out when the screen has just been
blacked — so their 3% spread is this run's noise floor, and the partial row is a 3.4x cut
that sits well outside it.

Defaults re-measured because the rule here says to when per-dot work is added, and this
adds a boolean test per dot: **64ms avg / 116 worst / 82% skipped**, against the 70ms / 94 /
81% in the Phase 3 table. In family, and on the slack side of it. That row has no partial
frames at all, which is not a sampling gap: at default rings the gate skips ~80% of frames
and `sinceClear` counts skips, so nearly every draw is the periodic repair. Delta redraw
cannot help there, and the point of the row is that it does not hurt.

## What makes it correct

Two remembered spans per ring, not one — the same shape as `drawnMark`/`previousMark` and
for the same reason. A partial draw is only correct in the buffer it lands in, and that
buffer was written two draws ago, so a dot is repainted when it differs from *either*
remembered span. That set is right for whichever buffer this draw is for without having to
know which one it is.

A delta may differ by span and nothing else. The two colours, the over flag, the ramp flag
and the backing are compared as **values** rather than inferred from the settings that move
them — power mode, theme, a ring reassignment — so a cause nobody thought of cannot slip
through. A ring whose key changed is repainted in full twice, because both buffers hold the
old tiers.

The mark erase blacks a whole cell, which is the whole of that dot. A full repaint used to
put the cross back as a matter of course and a delta will not, because that dot's tier did
not change — so the rubbed-out cells are forced back into the paint set.

Five tests drive the real renderer into a real Dc. The delta count is asserted against
`StatMap.isLit` as an oracle rather than a magic number (11 of 224 for a 5% span move), and
`theDeltaCoversBothBuffersNotJustTheLastDraw` measured 45 dots where the previous draw alone
would have given 23 — the failure it guards against looks right on screen and leaves every
other frame a step behind.

## The frame A/B, and what it did and did not settle

CLAUDE.md's rule is that adding per-dot work means re-measuring both rows, and this added
some to the Crossover's hot loop. Measured same-session, same machine, merge base against
this branch, one isolated simulator per leg and the legs alternated — two binaries with one
PRG stem cannot share an instance, because `load()` decides a push has landed by that file's
mtime and swapping them under one name never moves it.

    row                    base                    branch
    defaults, hands off    21ms / 27  80% skipped  20ms / 29  80% skipped
    defaults, hands ON     80ms / 101 80% skipped  79ms / 102 80% skipped
                          101ms / 159 76% skipped  96ms / 113 80% skipped
    seconds + temp         (leg invalid)           24-27ms / 93-111  0% skipped
    memory                 57k of 123k             59k of 123k

**No regression on the row that changed most.** Hands ON is where the gate replaced the bar
test, and it comes out level or slightly ahead on the worst frame. The +2k of memory is the
two new per-*ring* arrays and HandStyle; nothing per-dot was added to the cache.

Two caveats, both real:

- **the machine drifted between samples.** A leg's two samples differ by up to 4x in the
  hands-off row, which is load rather than code — exactly the trap CLAUDE.md warns about.
  The paired samples within a row are what to read, not any figure against another day's.
- **the seconds + temperature row never got a valid base leg.** The base binary was called
  `base.prg`, and simctl derives the settings filename from the PRG *stem*, so it wrote
  `BASE.SET` and the base leg quietly reported default rings for every row. Fixed by renaming
  the binary, but the rerun ran into a slept display and was abandoned rather than reported
  half-measured. The branch's own figure for that row, 24-27ms at 0% skipped, is the same
  class as the 31ms / 97 worst on record.

## Left on the table

- **The two-buffer assumption is now load-bearing in a second place.** `HOLD = 2` already
  assumes the Dc handed to `onUpdate` is at most double-buffered; delta redraw depends on
  the same fact, and gets a worse failure if it is wrong — a stale ring rather than a mark
  ghost. The simulator cannot answer it, and this remains the on-watch check Phase 3 left
  open. Unlike Phase 4's spike, this build *is* a wearable face, so `make install` and a
  minute of watching would settle it whenever the watch is free.
- **The scan is now the floor.** Delta redraw removed the drawing but kept the ~280-dot
  walk that finds the changed dots. Indexing each ring by position would let it jump
  straight to the arc that moved and skip the scan — worth roughly another 5ms of the 7,
  at the cost of one more per-dot array (~5.5KB against the ~34KB of headroom
  `theDotCacheFitsItsShareOfMemory` allows). Unmeasured; it is the obvious next phase.
- **`setPalette` is still standing**, at ~20ms flat with no dot loop at all. That is now
  *worse* than delta redraw on a partial frame and better on a repair, so if it is ever
  taken it is for the repair frame, and it still costs the fill-edge quantisation Phase 4
  described.

---

# Phase 7: make the frame independent of transition surfaces (spike)

**Current:** rejected on the physical Crossover.

Phase 6 proved the performance diagnosis and falsified its framebuffer model. Skipping
duplicate `onUpdate()` work made the widget list feel like a native Garmin face, but a
flashlight animation could leave transient copies of itself and the face could flash
black. More clears, a one-second `onHide()` debounce, and repainting an assumed pair of
buffers moved those symptoms without eliminating them.

The common cause is that the screen `Dc` is not application storage. Connect IQ may call
`onUpdate()` repeatedly during transitions, but gives the face no identity or persistence
contract for the surface behind any one call. Returning without drawing is cheap only if
the old pixels are still there; the physical failures show that is not always true.

The spike now keeps the complete face in one opaque 16-bit `WatchUi.Layer`. Garmin owns
compositing that layer during normal updates and animations. `FrameGate` decides only
whether the layer itself changed, and `MatrixRenderer` applies a change once to that one
authoritative surface. As a result there is no `onHide()` suppression, debounce, periodic
damage repair, held duplicate draw, alternate-buffer prime, second remembered span or
second remembered mark.

The state fingerprint is committed only after rendering succeeds. If a layer Dc is ever
unavailable, the fallback deliberately draws a complete direct frame on every callback
and never remembers those screen pixels; correctness degrades to the slower pre-layer
behaviour rather than to a black or stale frame.

## Evidence so far

- strict Crossover build succeeds;
- 127 Monkey C tests pass in the private simulator, including layer reuse, configuration
  invalidation, display-off behaviour and uncommitted-plan recovery;
- the live face loads in 4.5 seconds and renders correctly in a fresh private simulator;
- simulator application heap is 64.8 KiB of 123.8 KiB with the layer active;
- the 390 x 390 x 16-bit pixel store is about 304 KiB in Garmin's separate graphics pool,
  not in the application heap.

An older private simulator instance stopped accepting both this build and the known-good
Phase 6 build after a test run. A fresh isolated instance accepted the layer build
immediately, proving that timeout was harness state rather than a layer startup failure.

## Physical gate

Repeat wake, widget-list, flashlight, notification and settings transitions on the
Crossover. The spike passes only if all three hold together: native-feeling transition
latency remains, no flashlight positions survive, and no black frame appears. If native
layer compositing itself causes unacceptable load, the fallback design is an explicit
cached bitmap blitted on every callback; returning early against the screen `Dc` is no
longer an acceptable option.

It failed more strongly than Phase 6: the flashlight remained ghosted, and returning from
the widget list left the widget animation on screen indefinitely instead of loading the
face. The generic Layer contract is therefore not sufficient for a watch face beneath
these Crossover system transitions. An unchanged layer is not reliably recomposited.

---

# Phase 8: explicitly present a cached complete frame (spike)

**Current:** working cleanly in initial physical Crossover testing; Epix
physical verification pending.

The render target remains one authoritative 16-bit `BufferedBitmap`, but presentation is
now explicit. A changed fingerprint updates that buffer once; every visible `onUpdate()`
then calls `dc.drawBitmap(0, 0, frame)`, including unchanged transition callbacks. This is
the only model consistent with both physical observations: rerunning the 1,112-dot loop
for every callback causes navigation lag, while presenting nothing can expose a cleared
or stale transition surface.

The strong `BufferedBitmap` object and its Dc are retained for the app lifetime. Holding
only the `BufferedBitmapReference` would allow Garmin's graphics pool to purge dynamic
contents which it cannot reload from the executable. If allocation ever fails, the
fallback performs a complete direct redraw on every callback and never commits those
screen pixels as persistent state.

Version `0.1.0` begins explicit sideload versioning. The settings menu shows the compiled
version as its first row, so physical reports can identify the running PRG directly.

## Evidence so far

- strict builds succeed for Crossover and all four Epix 2 family targets;
- 137 Monkey C tests pass on each of those five targets, including the requirement that
  an unchanged callback skips buffer mutation but still increments presentation;
- 45 Python tests and the simulator-lock suite pass;
- live Crossover and Epix 2 simulator launches render correctly at their device-specific
  resolutions and hand styles;
- initial physical Crossover testing reports the transition fix working well;
- Epix performance and transition correctness remain the final device gate.
