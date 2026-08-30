import Toybox.Lang;

//! The hourly forecast's geometry: twelve blocks round the ring, three radial
//! sub-bands across its thickness.
//!
//! Every other source lights an *arc* — one contiguous span, the whole way
//! across the ring. This one lights twelve disjoint blocks, and how far each
//! reaches outward is the reading. That is a second shape, not a wider span,
//! so it gets its own definition here rather than bending StatMap's.
//!
//! **Where a block sits is not a rotation.** The hour hand at local hour `H`
//! points at clock position `H mod 12`, so the forecast for `N` hours ahead
//! must sit at `(H + N) mod 12` — which is exactly that forecast hour's own
//! hour-of-day, mod 12. So block `b` permanently means "the coming hour whose
//! local hour-of-day is congruent to b". RainForecast buckets straight into
//! that index and nothing downstream rotates anything, ever. If a table here
//! ever needs turning once an hour, this was built the hard way.
//!
//! Like StatMap.litBetween(), the lit test below is the readable definition and
//! MatrixRenderer inlines its body — the same trade, and the same obligation:
//! theHourlyLitTestAgreesWithTheRenderer pins the two together at the block
//! edge, the gutter edge and every sub-band edge, which is where a copied
//! comparison drifts.
module HourBands {

    //! Twelve hours ahead, one per hour mark on the dial.
    const HOURS = 12;

    //! Three radial sub-bands: >=25% lights one, >=50% two, >=75% all three.
    //!
    //! Three rather than four, and that was measured rather than chosen. A ring
    //! is 42px thick, so four sub-bands are 10.5px against the lattice's 10px
    //! pitch and the two beat against each other: ring 1 splits four ways into
    //! 7.0 / 5.7 / 9.0 / 6.7 dots per block, which reads as an uneven stack.
    //! Split three ways it is 8.3 / 9.0 / 11.0, and ring 0 is 11.0 / 12.3 /
    //! 13.0. The source has to work on either ring, so three wins.
    const BANDS = 3;

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

    //! The block's share of its wedge, in position units: a dot whose fraction
    //! into the wedge is at or past this is in the gutter.
    const FILL = HOUR_BLOCK_DEGREES / WEDGE_DEGREES;

    //! A block the forecast said nothing about. Not a tier — tiers are 0-3 and
    //! 0 is a real answer meaning "known, and dry".
    const UNKNOWN = -1;

    //! Which hour block a position falls in.
    //!
    //! Positions run 0.0 up to but not including 1.0, so this cannot exceed
    //! HOURS - 1 — but the renderer's table carries a thirteenth entry
    //! mirroring the first anyway, because float arithmetic near the wrap is
    //! exactly the kind of thing that yields a 12 once on a watch and never in
    //! a test.
    function blockOf(position as Float) as Number {
        var at = (position * HOURS).toNumber();
        return (at >= HOURS) ? (HOURS - 1) : at;
    }

    //! Is this position inside its block, rather than in the gutter after it?
    //!
    //! The block occupies the *leading* part of each wedge, so every boundary
    //! lands on an hour mark and the blocks line up with the dial.
    function insideBlock(position as Float) as Boolean {
        var at = position * HOURS;
        return (at - at.toNumber()) < FILL;
    }

    //! The tier packed into `levels` for this block, or UNKNOWN.
    //!
    //! Two words rather than one three-bit field per block: twelve blocks of
    //! three bits is 36 bits, which no Float round-trips, and both of these
    //! have to survive FrameGate's element-wise float comparison intact.
    //! Packed this way `levels` tops out at 0xFFFFFF and `known` at 0xFFF, both
    //! inside a Float's exact integer range.
    function tierOf(levels as Number, known as Number,
                    block as Number) as Number {
        if (((known >> block) & 1) == 0) {
            return UNKNOWN;
        }
        return (levels >> (block * 2)) & 3;
    }

    //! Is a dot lit, given the per-block outer edges the renderer precomputes?
    //!
    //! `edges[b]` is the squared radius a dot must be within to be lit in block
    //! b — zero for a block that is dry or unknown, since no dot's squared
    //! radius is below the hub's. This is the shape MatrixRenderer inlines.
    function litAt(position as Float, radiusSq as Number,
                   edges as Array<Number>) as Boolean {
        var at = position * HOURS;
        var block = at.toNumber();
        if ((at - block) >= FILL) {
            return false;                   //! the gutter after the block
        }
        return radiusSq <= edges[block];
    }
}
