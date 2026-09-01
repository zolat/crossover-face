import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

//! The day of the month, written into the *grain* of the dot field rather than
//! on top of it. Pure geometry and arithmetic — nothing here draws.
//!
//! Every dot on this face is a cross of two five-pixel strokes, nine lit
//! pixels. A **struck** dot draws one of those strokes and not the other: five
//! pixels, in the same cell, of the same colour, carrying whatever its ring was
//! already saying. A patch of struck dots reads as a slightly thinner texture,
//! and a numeral drawn in them is a watermark — legible when you look for it,
//! and gone when you are reading the rings.
//!
//! **It cannot cost luminance, and that is not an argument but an arithmetic
//! fact**: a struck dot lights a strict subset of the pixels the same dot lit
//! before, so the frame's total can only fall. That is what makes this free
//! where every other addition to the face has had to be measured against the
//! 10% budget. `strikingADotOnlyRemovesLight` asserts it rather than assuming.
//!
//! Rotation was tried first and rejected on the mockups: turning a dot 45
//! degrees is genuinely free too — the same nine pixels, and the measured
//! luminance did not move in the sixteenth digit — but at a five-pixel dot a
//! `+` and a `×` are too close to tell apart, and a numeral made of them read
//! as a faint sheen rather than a number at 1:1, let alone on a wrist. The
//! density step a dropped arm gives is what actually carries the shape.
//! `tools/mockup.py` renders both; `build/gate/true-size.png` is the comparison.
module DateGlyph {

    //! Which stroke a struck dot keeps: the 45-degree cross's first arm.
    //!
    //! Taken out of `DotGrid.ARMS` rather than written as a pair of numbers,
    //! so the stroke is one of the orientations the lattice already defines and
    //! a change to the dot size reaches it.
    const ARM = 2 * DotGrid.ARM_VALUES;

    //! Pixels a struck dot lights, against `2 * DOT - 1` for a whole cross.
    const STROKE_PIXELS = DotGrid.DOT;

    // --- the font ------------------------------------------------------------

    //! Cells of the lattice per pixel of the font.
    //!
    //! Two, not one, and the mockups settled it. A 3x5 digit drawn one cell to
    //! the pixel is 30x50px, which sounds ample and is not: a stroke one dot
    //! wide has no coherent area to read as a stroke, and the numeral
    //! disappears into the field. At two cells the strokes are 20px wide and
    //! the number is there.
    const SCALE = 2;

    const FONT_COLS = 3;
    const FONT_ROWS = 5;
    const FONT_BITS = FONT_COLS * FONT_ROWS;

    //! Font columns across: two digits with a single-column gutter between.
    const FONT_SPAN = 2 * FONT_COLS + 1;

    const COLS = FONT_SPAN * SCALE;         //! 14 lattice cells wide
    const ROWS = FONT_ROWS * SCALE;         //! 10 lattice cells tall
    const CELLS = COLS * ROWS;

    //! The font column the gutter occupies.
    const GUTTER = FONT_COLS;

    //! Where the window's top-left cell sits in the lattice.
    //!
    //! Horizontally centred — `ORIGIN_COL` plus half of COLS is exactly the
    //! grid's own centre — and in the lower half, which is where a date window
    //! belongs on a dial and the only place a block this size fits without the
    //! hand pivot punching a hole in it.
    const ORIGIN_COL = 12;
    const ORIGIN_ROW = 23;

    //! 3x5 digits, row-major, bit 14 top-left. Fifteen bits each.
    //!
    //! Flat Numbers rather than an array of arrays, for the reason
    //! `DotGrid.ARMS` and `Palette.THEMES` are flat: a const array of arrays
    //! resolves in the simulator and comes back empty on the watch.
    const DIGITS = [
        0x7B6F,             //! 0
        0x2C97,             //! 1
        0x73E7,             //! 2
        0x73CF,             //! 3
        0x5BC9,             //! 4
        0x79CF,             //! 5
        0x79EF,             //! 6
        0x7249,             //! 7
        0x7BEF,             //! 8
        0x7BCF              //! 9
    ] as Array<Number>;

    //! Is this pixel of this digit lit?
    function digitLit(digit as Number, col as Number, row as Number) as Boolean {
        return ((DIGITS[digit] >> (FONT_BITS - 1 - (row * FONT_COLS + col)))
                & 1) == 1;
    }

    //! Is this cell of the window struck, for a given day?
    //!
    //! Cell coordinates are the window's own, 0-based. The readable definition:
    //! `isGlyphDot()` and the cell tables below both have to agree with it.
    function cellLit(day as Number, col as Number, row as Number) as Boolean {
        var fontCol = col / SCALE;
        if (fontCol == GUTTER) {
            return false;
        }
        var digit = (fontCol < GUTTER) ? (day / 10) : (day % 10);
        return digitLit(digit % 10, fontCol % (GUTTER + 1), row / SCALE);
    }

    // --- the lattice half of the cache ---------------------------------------
    //
    // Which dot sits in each window cell depends on the lattice and nothing
    // else, so it is worked out once per DotGrid.build() and survives every
    // date change. The scan runs in index order, which is what makes the list
    // below **already sorted**: no sort, and no reverse map from cell to dot.

    var cellDot as Array<Number> = [] as Array<Number>;  //! dot index, ascending
    var cellAt as Array<Number> = [] as Array<Number>;   //! its cell, row * COLS + col
    var cells as Number = 0;
    var builtFor as Number = -1;        //! the DotGrid.generation these describe

    // --- the date half -------------------------------------------------------

    //! The struck dots, ascending. Ascending is not decoration: the renderer
    //! walks its rings in this same order and keeps a cursor, so membership
    //! costs one integer comparison per dot rather than a lookup.
    var index as Array<Number> = [] as Array<Number>;
    var lit as Number = 0;

    //! Where each ring's slice of `index` begins, with a final total. A ring
    //! the gate left clean is skipped entirely, so the cursor cannot be carried
    //! from the ring before — it is re-seeded per ring from here.
    var firstFor as Array<Number> = [] as Array<Number>;

    var shownDay as Number = -1;
    var shownFor as Number = -1;        //! the generation `index` was filtered at

    //! Bring both halves up to date for this day. Cheap when nothing moved.
    function ensure(day as Number) as Void {
        if (builtFor != DotGrid.generation) {
            buildCells();
        }
        if (shownDay != day || shownFor != builtFor) {
            filter(day);
        }
    }

    //! Which dots fall inside the window, in ascending index order.
    function buildCells() as Void {
        if (cellDot.size() != CELLS) {
            cellDot = new [CELLS] as Array<Number>;
            cellAt = new [CELLS] as Array<Number>;
        }
        var found = 0;
        var total = DotGrid.count;
        var xs = DotGrid.xs;
        var ys = DotGrid.ys;
        var origin = DotGrid.LAST * DotGrid.STEP;
        for (var i = 0; i < total; i++) {
            var row = (ys[i] + origin) / DotGrid.PITCH - ORIGIN_ROW;
            if (row < 0 || row >= ROWS) {
                continue;
            }
            var col = (xs[i] + origin) / DotGrid.PITCH - ORIGIN_COL;
            if (col < 0 || col >= COLS) {
                continue;
            }
            cellDot[found] = i;
            cellAt[found] = row * COLS + col;
            found++;
        }
        cells = found;
        builtFor = DotGrid.generation;
        shownDay = -1;                  //! the indices below name the old dots
    }

    //! Filter the window's dots down to the ones this day strikes.
    function filter(day as Number) as Void {
        if (index.size() != CELLS) {
            index = new [CELLS] as Array<Number>;
        }
        var ringCount = StatMap.RINGS;
        if (firstFor.size() != ringCount + 1) {
            firstFor = new [ringCount + 1] as Array<Number>;
        }
        var ringStart = DotGrid.ringStart;
        var ring = 0;
        firstFor[0] = 0;
        var found = 0;
        for (var k = 0; k < cells; k++) {
            var at = cellAt[k];
            if (!cellLit(day, at % COLS, at / COLS)) {
                continue;
            }
            var dot = cellDot[k];
            // The dots arrive in index order and the rings are contiguous
            // ascending ranges of that order, so the slice boundaries fall out
            // of the same walk rather than needing a search.
            while (ring < ringCount && dot >= ringStart[ring + 1]) {
                ring++;
                firstFor[ring] = found;
            }
            index[found] = dot;
            found++;
        }
        while (ring < ringCount) {
            ring++;
            firstFor[ring] = found;
        }
        lit = found;
        shownDay = day;
        shownFor = builtFor;
    }

    //! Is this dot struck? The readable definition, used by the tests and by
    //! anything not in the render loop.
    //!
    //! The renderer inlines a cursor walk of `index` instead, which is the same
    //! trade `StatMap.litBetween()` gets and carries the same obligation:
    //! `theGlyphMatchesItsReadableDefinition` pins the two together over every
    //! dot in the lattice.
    function isGlyphDot(i as Number) as Boolean {
        if (shownDay < 0) {
            return false;
        }
        var origin = DotGrid.LAST * DotGrid.STEP;
        var row = (DotGrid.ys[i] + origin) / DotGrid.PITCH - ORIGIN_ROW;
        var col = (DotGrid.xs[i] + origin) / DotGrid.PITCH - ORIGIN_COL;
        if (row < 0 || row >= ROWS || col < 0 || col >= COLS) {
            return false;
        }
        return cellLit(shownDay, col, row);
    }

    // --- reading the clock ---------------------------------------------------

    const SECONDS_PER_DAY = 86400;

    var day as Number = 1;
    var dayKey as Number = -1;          //! the local day number `day` is for

    //! Today's day of the month.
    //!
    //! `Gregorian.info()` is the expensive way to ask and this is called on
    //! every frame the watermark is on — including the ones the gate goes on to
    //! skip, which is the average this would show up in. So the *key* is
    //! arithmetic on the epoch second, which changes once a day, and the
    //! calendar call happens only when it does.
    function today() as Number {
        var now = Time.now().value() +
                  System.getClockTime().timeZoneOffset;
        var key = now / SECONDS_PER_DAY;
        if (key != dayKey) {
            day = Gregorian.info(Time.now(), Time.FORMAT_SHORT).day;
            dayKey = key;
        }
        return day;
    }
}
