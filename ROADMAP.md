# Roadmap

**Current:** done — the block ring is graded sixteen ways; the on-watch check is still below.

Out-of-band feature work, not a phase of the performance roadmap that follows: that one is
complete and this does not extend it.

- [x] Rain, next 12h — an hourly forecast in one ring
- [x] Block levels — width as the second axis, so a block reads sixteen ways rather than four

Plans: `~/.claude/plans/i-want-to-plan-starry-graham.md`,
`~/.claude/plans/encapsulated-finding-owl.md`

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

## Left on the table

- ~~**Nothing has been seen.**~~ Settled: the face has now been screenshotted awake with a
  graded forecast on the outer ring, and the lit pixels per block were counted off the
  capture — 0% and 5% dark, 10% a two-dot pip, monotone round to 100%, the unforecast hour
  on the dim tier. The earlier *could not create image from window* was the Mac display
  asleep, not a missing permission; `caffeinate -u` wakes it, `-d` only stops it sleeping
  again. It needed a temporary stub for the forecast and a forced ring assignment, so the
  *data path* from `Weather` is still unexercised — see the last bullet.
- **The gutter's alignment is unexamined.** Blocks occupy the *leading* 22.5 degrees of each
  wedge, so every boundary lands on an hour mark and the hour hand sits in its own block
  from :00 to :45 and in the gutter after that. Centring the block instead keeps the hand
  inside its band the whole hour but moves the boundaries off the marks. One constant either
  way, and it should be decided looking at a render.
- **On-watch verification.** `getHourlyForecast()` returns null in the simulator, so every
  hour is unknown there and the whole ring draws the dim tier. Nothing has exercised the
  bucketing against a real forecast, and the array's length is undocumented — the dim tier
  exists precisely because it may come back shorter than twelve.

# Previously: the frame budget (complete)

**Current:** done — Phase 5 landed the lever Phase 4 picked.

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
