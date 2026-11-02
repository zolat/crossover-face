import Toybox.Lang;

//! The block ring's geometry: twelve blocks round the ring, three radial
//! sub-bands across its thickness, and one partial band whose *width* carries
//! whatever the bands cannot.
//!
//! Every other source lights an *arc* — one contiguous span, the whole way
//! across the ring. This one lights twelve disjoint blocks, and how much of
//! each is filled is the reading. That is a second shape, not a wider span,
//! so it gets its own definition here rather than bending StatMap's.
//!
//! **Nothing here is about rain.** The forecast is the first source to fill
//! this shape, not the only one that can: a block is a level from 0 to LEVELS
//! and where that level came from is Source's business. Anything with one
//! reading per clock position — the next twelve hours of something, or twelve
//! of something else — packs through raise() and draws through the same loop.
//!
//! **Where a block sits is not a rotation.** The hour hand at local hour `H`
//! points at clock position `H mod 12`, so the forecast for `N` hours ahead
//! must sit at `(H + N) mod 12` — which is exactly that forecast hour's own
//! hour-of-day, mod 12. So block `b` permanently means "the coming hour whose
//! local hour-of-day is congruent to b". HourlyWeatherData buckets straight into
//! that index and nothing downstream rotates anything, ever. If a table here
//! ever needs turning once an hour, this was built the hard way.
//!
//! Like StatMap.litBetween(), the lit test below is the readable definition and
//! MatrixRenderer inlines its body — the same trade, and the same obligation:
//! theHourlyLitTestAgreesWithTheRenderer pins the two together at the block
//! edge, the gutter edge, every sub-band edge and both sides of the partial
//! band's window, which is where a copied comparison drifts.
module HourBands {

    //! Twelve hours ahead, one per hour mark on the dial.
    const HOURS = 12;

    //! Three radial sub-bands across the ring's thickness.
    //!
    //! Three rather than four, and that was measured rather than chosen. A ring
    //! is 42px thick, so four sub-bands are 10.5px against the lattice's 10px
    //! pitch and the two beat against each other: ring 1 splits four ways into
    //! 7.0 / 5.7 / 9.0 / 6.7 dots per block, which reads as an uneven stack.
    //! Split three ways it is 8.3 / 9.0 / 11.0, and ring 0 is 11.0 / 12.3 /
    //! 13.0. The source has to work on either ring, so three wins.
    //!
    //! The lattice caps the *radial* axis at three and there is no arguing
    //! with it. It does not cap the angular one anything like as hard — a
    //! block is eight to thirteen dots wide — which is the axis LEVELS spends.
    const BANDS = 3;

    //! The top of the scale. A block's level runs 0 to LEVELS inclusive, so
    //! sixteen readings an hour where the sub-bands alone give four.
    //!
    //! **Linear in area, and the top of the scale is the whole block.** Level
    //! L fills `L * BANDS / LEVELS` bands: the whole part is that many
    //! full-width sub-bands, the remainder is the angular half-width of the
    //! next band out. Level LEVELS is exactly the three full bands the old top
    //! tier drew, which is what leaves every luminance bound where it was —
    //! nothing this scale can draw was not already drawable.
    //!
    //! Sixteen rather than eight because the packing costs the same either
    //! way: four bits a block is what fits six blocks in a word (see raise()),
    //! and three bits would need the same two words for half the resolution.
    const LEVELS = 15;

    //! A block the source said nothing about. Not a level — levels run 0 to
    //! LEVELS and 0 is a real answer meaning "known, and empty".
    const UNKNOWN = -1;

    //! Every block known. Kept with the packed shape rather than with any one
    //! producer: held-back always-on needs to say "known and empty everywhere",
    //! and rain, UV and history all use the same known-bit word.
    const ALL_KNOWN = (1 << HOURS) - 1;

    // --- packing -------------------------------------------------------------
    //
    // Two words of levels and one of known bits, rather than a twelve-entry
    // array: they ride in the frame print, which FrameGate compares as floats
    // element by element, and they must survive that intact. Four bits a block
    // over six blocks is 24 bits, so each levels word tops out at 0xFFFFFF and
    // `known` at 0xFFF — all three inside the range a Float represents exactly,
    // which theHourlyMasksSurviveTheFramePrint pins.
    //
    // Two words and not one because twelve blocks at four bits is 48 bits, and
    // nothing here round-trips that: not a Float, not a Number.

    const LEVEL_BITS = 4;
    const LEVEL_MASK = 15;
    const BLOCKS_PER_WORD = 6;

    //! How many words of levels a full set of blocks takes. Two.
    const LEVEL_WORDS = HOURS / BLOCKS_PER_WORD;

    //! Which levels word holds this block, and how far into it.
    function wordOf(block as Number) as Number {
        return block / BLOCKS_PER_WORD;
    }

    function shiftOf(block as Number) as Number {
        return (block % BLOCKS_PER_WORD) * LEVEL_BITS;
    }

    //! Raise this block to `level` in a two-word levels array, never lower it.
    //!
    //! **Never lowered, and that is not an optimisation.** A source may offer
    //! two entries for one block — Garmin should give one forecast an hour, but
    //! nothing documents it — and "how much in this hour" has an obvious answer
    //! there: whichever said more. Taking the maximum is also what makes the
    //! merge order-independent, so a reordered source array cannot change the
    //! picture.
    //!
    //! Subtracting the existing bits rather than masking them out: they are
    //! exactly the bits being replaced, so the subtraction clears them, and it
    //! avoids leaning on how Monkey C widens a bitwise complement.
    function raise(words as Array<Number>, block as Number,
                   level as Number) as Void {
        var word = wordOf(block);
        var shift = shiftOf(block);
        var packed = words[word];
        var existing = (packed >> shift) & LEVEL_MASK;
        if (level <= existing) {
            return;
        }
        setLevel(words, block, level);
    }

    //! Set one block exactly, including lowering it.
    //!
    //! Forecast duplicates use raise(), because the strongest reading wins.
    //! A sampled level is different: Body Battery can fall as well as rise, so
    //! its live hour must be able to replace yesterday's larger nibble. This is
    //! the one exact-write primitive for the packed shape.
    function setLevel(words as Array<Number>, block as Number,
                      level as Number) as Void {
        if (level < 0) { level = 0; }
        if (level > LEVELS) { level = LEVELS; }
        var word = wordOf(block);
        var shift = shiftOf(block);
        var packed = words[word];
        var existing = (packed >> shift) & LEVEL_MASK;
        words[word] = packed - (existing << shift) + (level << shift);
    }

    //! This block's level, or UNKNOWN.
    //!
    //! Takes the two words loose rather than as an array, because the renderer
    //! reads them straight out of StatMap's flat channel and the tests build
    //! them by hand — neither has an array to hand at that point.
    function levelAt(lo as Number, hi as Number, known as Number,
                     block as Number) as Number {
        if (((known >> block) & 1) == 0) {
            return UNKNOWN;
        }
        var packed = (block < BLOCKS_PER_WORD) ? lo : hi;
        return (packed >> shiftOf(block)) & LEVEL_MASK;
    }

    //! A 0.0-1.0 reading as a level, so a second source filling this shape
    //! reuses the scale rather than re-deriving it.
    //!
    //! Truncating, which is what makes an all-but-empty block read empty: a
    //! reading has to reach a full 1/LEVELS of the scale before it lights
    //! anything. Anything else would put a pip on every block of a dry day.
    function levelFromFraction(fraction as Float) as Number {
        if (fraction <= 0.0) {
            return 0;
        }
        var level = (fraction * LEVELS).toNumber();
        return (level > LEVELS) ? LEVELS : level;
    }

    // --- the fill ------------------------------------------------------------

    //! How much of each hour's 30 degrees the block occupies. The rest is a
    //! dark gutter, which is what keeps the hours countable rather than
    //! merging a wet afternoon into one anonymous arc.
    //!
    //! **The one knob.** Everything below derives from it, so widening the
    //! block to 30.0 (no gutter) or narrowing it to 15.0 needs no other edit
    //! and breaks no test — everyHourBlockLeavesADarkGutter is written against
    //! this constant rather than against 22.5.
    const HOUR_BLOCK_DEGREES = 22.5;

    const WEDGE_DEGREES = 360.0 / HOURS;

    //! The block's share of its wedge, in position units.
    const FILL = HOUR_BLOCK_DEGREES / WEDGE_DEGREES;

    //! How far into its wedge a block starts — half the gutter, so the other
    //! half falls after it.
    //!
    //! **The block is centred in its hour slot, and it did not used to be.** It
    //! sat at the leading edge, starting exactly on hour mark H with the whole
    //! gutter bunched up before mark H+1. That put every block's centre 11.25
    //! degrees after its mark where the slot's centre is 15 — 3.75 degrees
    //! anticlockwise, about 12px of arc on the outer ring, and plainly visible
    //! on the watch against the printed dial.
    //!
    //! Centred, each hour mark sits in the middle of a 7.5-degree gutter and
    //! each block sits in the middle of the arc the hour hand sweeps during
    //! that hour — so the hand is inside its own block from :07.5 to :52.5,
    //! symmetric, rather than leaving early at :45.
    const LEAD = (1.0 - FILL) / 2.0;

    //! Where the block ends, so the gutter test is two comparisons rather than
    //! an addition per dot.
    const TRAIL = LEAD + FILL;

    //! The middle of the block, which the partial band grows out from in both
    //! directions — and which is **exactly the middle of the wedge**.
    //!
    //! `LEAD + FILL/2` reduces to `1/2` for any FILL at all, because LEAD is
    //! defined as half of what FILL leaves over. That is the whole point of
    //! centring: the block's centre is the slot's centre whatever the block
    //! width, so HOUR_BLOCK_DEGREES stays the one knob it claims to be.
    const BLOCK_CENTRE = LEAD + FILL / 2.0;

    //! The level that fills exactly one whole sub-band and no more. BANDS
    //! divides LEVELS, so the band edges land on levels rather than between
    //! them and "one band" is sayable without a magic number.
    const LEVELS_PER_BAND = LEVELS / BANDS;

    //! How many whole sub-bands a level fills, 0 to BANDS.
    function fullBandsFor(level as Number) as Number {
        return (level * BANDS) / LEVELS;
    }

    //! How far into the *next* band out the level reaches, 0.0 to below 1.0.
    //!
    //! Zero means the level lands exactly on a band edge and there is no
    //! partial band at all — which is what level 0 and level LEVELS both do,
    //! from opposite ends.
    function partialFractionFor(level as Number) as Float {
        return ((level * BANDS) % LEVELS).toFloat() / LEVELS;
    }

    //! Half the width of the partial band's window, in wedge units. Zero when
    //! the level has no partial band.
    //!
    //! **There is no minimum width here, and that was measured twice rather
    //! than assumed.** The obvious worry is that a level-1 window — a fifth of
    //! a band — falls clean between two dots of a square lattice and the bottom
    //! of the scale draws nothing, which is the one failure this scale exists
    //! to prevent. On the offered rings it does not happen: every block lights
    //! at least one dot at every level, monotonically, which
    //! everyNonZeroLevelLightsAtLeastOneDot and aLevelIsMonotonicInDotsLit keep
    //! true.
    //!
    //! Centring the block (see LEAD) made that closer than it was, and a floor
    //! was measured again there rather than assumed to help. It does not: it
    //! puts blocks 1, 4, 7 and 10 with their centres on the lattice's 45-degree
    //! diagonals, where dots sit further apart, so level 1 draws 1 dot at those
    //! four hours and 3 at the rest. A floor of a lattice pitch or less changes
    //! nothing at all, and one of 1.4 pitches evens level 1 up to 3-4 dots —
    //! which is exactly what level 2 draws, collapsing two rungs into one. A
    //! lost rung costs more than the unevenness, so the floor stays out. If
    //! either test ever does fail, a floor sized off DotGrid.markerHalf — which
    //! solves this same problem for the temperature mark — is the fix, and it
    //! has to be checked against level 2 rather than only against zero.
    function partialHalfFor(level as Number) as Float {
        return (FILL / 2.0) * partialFractionFor(level);
    }

    //! The narrowest partial window each ring draws, in wedge units. Zero —
    //! no floor — on the outer two, for the reasons above.
    //!
    //! **Ring 2 is where the floor finally earned its place.** Once block
    //! sources were offered there, its level-1 window (0.075 of a wedge) fell
    //! between dots in eight (block, level) pairs on the 416 and 454 lattices
    //! and in one on the 390, so a light-drizzle hour drew exactly what a dry
    //! one does. 0.12 lights a dot in every block at every level on all three
    //! screens and leaves levels 1 and 2 as distinct as they already were (the
    //! same in 4 of 12 blocks, unfloored or floored); 0.15 merges them in all
    //! twelve. It only ever raises the windows of levels 1, 6 and 11, whose
    //! partial band is a fifth of a band. Flat, for the reason DotGrid.ARMS is.
    //! One entry per ring any watch has, five; rings past BLOCKS_TOP_RING never
    //! draw blocks, so their floors are never read in production.
    const WINDOW_FLOOR = [0.0, 0.0, 0.12, 0.0, 0.0] as Array<Float>;

    //! partialHalfFor() on a particular ring: floored, but still zero where
    //! the level has no partial band, so a level on a band edge stays exact.
    function partialHalfOn(level as Number, ring as Number) as Float {
        var window = partialHalfFor(level);
        var floor = WINDOW_FLOOR[ring];
        return (window > 0.0 && window < floor) ? floor : window;
    }

    //! Which hour block a position falls in.
    //!
    //! Positions run 0.0 up to but not including 1.0, so this cannot exceed
    //! HOURS - 1 — but the renderer's tables carry a thirteenth entry
    //! mirroring the first anyway, because float arithmetic near the wrap is
    //! exactly the kind of thing that yields a 12 once on a watch and never in
    //! a test.
    function blockOf(position as Float) as Number {
        var at = (position * HOURS).toNumber();
        return (at >= HOURS) ? (HOURS - 1) : at;
    }

    //! Is this position inside its block, rather than in a gutter?
    //!
    //! The block sits in the middle of its wedge, so there is gutter on both
    //! sides of it and the hour marks fall in the middle of those gutters.
    function insideBlock(position as Float) as Boolean {
        var at = position * HOURS;
        var into = at - at.toNumber();
        return into >= LEAD && into < TRAIL;
    }

    //! What DotGrid.blockAt stores for a dot at this position: its block, or
    //! GUTTER when it sits in the gap either side of one. Fixed geometry —
    //! LEAD and TRAIL are constants — which is what lets it be cached per dot.
    const GUTTER = HOURS;

    function blockCodeOf(position as Float) as Number {
        return insideBlock(position) ? blockOf(position) : GUTTER;
    }

    //! litAt(), written against the cached block code instead of the
    //! position alone. This is the shape MatrixRenderer inlines now: the
    //! block and the gutter come from DotGrid.blockAt, and only a dot inside
    //! the partial band's radius works out how far into its block it sits.
    //! theCachedBlockCodeLightsWhatLitAtDoes holds the two to each other.
    function litInBlock(code as Number, position as Float, radiusSq as Number,
                        fullEdges as Array<Number>, partEdges as Array<Number>,
                        partLo as Array<Float>,
                        partHi as Array<Float>) as Boolean {
        if (code == GUTTER) {
            return false;
        }
        if (radiusSq <= fullEdges[code]) {
            return true;
        }
        if (radiusSq > partEdges[code]) {
            return false;
        }
        var into = position * HOURS - code;
        return into > partLo[code] && into < partHi[code];
    }

    //! Is a dot lit, given the per-block tables the renderer precomputes?
    //!
    //! `fullEdges[b]` is the squared radius a dot must be within to be lit
    //! anywhere across the block's width — zero for a block that is empty or
    //! unknown, since no dot's squared radius is below the hub's.
    //! `partEdges[b]` is the same for the one partial band beyond it, and
    //! `partLo`/`partHi` are the two sides of the window that band is drawn
    //! through. This is the shape MatrixRenderer inlines.
    function litAt(position as Float, radiusSq as Number,
                   fullEdges as Array<Number>, partEdges as Array<Number>,
                   partLo as Array<Float>,
                   partHi as Array<Float>) as Boolean {
        var at = position * HOURS;
        var block = at.toNumber();
        var into = at - block;
        if (into < LEAD || into >= TRAIL) {
            return false;                   //! a gutter, either side
        }
        if (radiusSq <= fullEdges[block]) {
            return true;
        }
        return radiusSq <= partEdges[block] &&
               into > partLo[block] && into < partHi[block];
    }
}
