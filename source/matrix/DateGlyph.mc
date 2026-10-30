import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

//! The day of the month, drawn *through* the dot field rather than on top of it.
//!
//! The numeral's own dots are drawn like every other: same cross, same colour,
//! carrying whatever its ring was already saying. What makes it a number is a
//! faint **outline joining them** — straight lines from dot centre to dot
//! centre, tracing the numeral's edge, at `linePercent()` of the colour of the
//! dot each line leaves from. It is the dots being connected, not a figure laid
//! over them, so it reads as part of the lattice.
//!
//! Three things settled on the wrist, after the mockups had lied once:
//!
//! - **A struck dot does not read.** The previous watermark drew one stroke of
//!   each numeral dot instead of two. It measured well and was invisible on
//!   the watch — a 5-against-9-pixel density step is lost in a field whose
//!   rings already change colour and tier under the window.
//! - **The line runs through the dot centres, never along cell edges.** An
//!   outline five pixels off every dot fights the grid; one through the
//!   centres *is* the grid.
//! - **65%, chosen between 50, 65 and 80 a minute apart on the watch.** 100
//!   was too obvious and 40 vanished on the AMOLED, which crushes dark levels
//!   a monitor shows.
//!
//! **It is awake-only.** Always-on carries no date at all: a line, unlike a
//! cross, does not escape itself when the burn-in drift moves the field by
//! one `DOT`, so some of its pixels would sit lit through two of the four
//! drift phases against one for every dot pixel. Waking draws the outline in,
//! growing along each loop of the numeral from its top-left dot — the dots
//! being connected, in front of you. CrossoverView drives that; the order is
//! `segDepth` here.
module DateGlyph {

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
    //! Derived from the selected lattice rather than pinned to the original
    //! 38x38 one: every supported grid is even, so this keeps the glyph
    //! horizontally centred and its top edge 45px below the pivot at every
    //! screen size.
    const ORIGIN_COL = (DotGrid.COLS - COLS) / 2;
    const ORIGIN_ROW = (DotGrid.ROWS / 2) + 4;

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

    //! Is this cell of the window part of the numeral, for a given day?
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

    //! The numeral's dots, ascending. Ascending is not decoration: the renderer
    //! walks its rings in this same order and keeps a cursor, so membership
    //! costs one integer comparison per dot rather than a lookup.
    var index as Array<Number> = [] as Array<Number>;
    var lit as Number = 0;

    //! The window cell each entry of `index` sits in, row * COLS + col.
    var indexCell as Array<Number> = [] as Array<Number>;

    //! The colour each numeral dot was last drawn in, by its position in
    //! `index`. The renderer writes it as it draws the dot, -1 until it has:
    //! the outline is inked in the colour of the dot each line leaves from, and
    //! that colour is everything the renderer decided — tier, ramp, block,
    //! hand — which nothing outside the dot loop could cheaply say again.
    var colours as Array<Number> = [] as Array<Number>;

    //! Whether the frame being drawn carries the date. Set by the view, which
    //! owns the decision (awake, setting on, hands not in the way); read by the
    //! renderer, which only needs to know whether to record colours.
    var active as Boolean = false;

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

    //! Filter the window's dots down to the ones this day's numeral covers.
    function filter(day as Number) as Void {
        if (index.size() != CELLS) {
            index = new [CELLS] as Array<Number>;
            indexCell = new [CELLS] as Array<Number>;
            colours = new [CELLS] as Array<Number>;
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
            indexCell[found] = at;
            found++;
        }
        while (ring < ringCount) {
            ring++;
            firstFor[ring] = found;
        }
        lit = found;
        shownDay = day;
        shownFor = builtFor;
        // Reset rather than kept: these name yesterday's dots. The renderer
        // refills them on the frame the new day draws on, which is a full
        // clear because the day is in the field print.
        for (var k = 0; k < CELLS; k++) {
            colours[k] = -1;
        }
    }

    // --- the outline ------------------------------------------------------------

    //! The connecting lines' brightness, as a percentage of the colour of the
    //! dot each leaves from: the three levels compared a minute apart on the
    //! watch, indexed by `StatMap.dateOutline`. 65 was the pick and is the
    //! default; 40 vanished on the AMOLED and 100 was too obvious, so neither
    //! end is offered.
    const LINE_PERCENTS = [50, 65, 80] as Array<Number>;

    //! The level the wearer chose.
    function linePercent() as Number {
        return LINE_PERCENTS[StatMap.dateOutline];
    }

    //! A line fills only the gap between two crosses, never their arms: a faint
    //! line painted over an arm would dim the dot it runs into. Arms reach
    //! `DOT / 2` from a centre, so the gap starts one pixel past that and runs
    //! to one pixel short of the next dot's arm.
    const GAP_FROM = DotGrid.DOT / 2 + 1;
    const GAP_LENGTH = DotGrid.PITCH - 2 * GAP_FROM + 1;

    //! The outline: segments joining two entries of `index` one pitch apart,
    //! and how far round its loop each one sits, which is the reveal order.
    var segA as Array<Number> = [] as Array<Number>;
    var segB as Array<Number> = [] as Array<Number>;
    var segDepth as Array<Number> = [] as Array<Number>;

    //! The colour each segment is standing in the buffer in, -1 where it is
    //! not drawn. drawContour() repaints only the segments that differ, which
    //! is what keeps a drawn frame from paying ~90 native calls: measured at
    //! 37ms a frame on the seconds row when every segment was inked every time,
    //! against 16ms for the renderer's whole delta.
    var segInked as Array<Number> = [] as Array<Number>;

    //! How many segments the last drawContour() actually drew. The screen
    //! cannot be read back, so this is what holds the skip to its contract.
    var inked as Number = 0;
    var segments as Number = 0;
    var maxDepth as Number = 0;

    //! The day and lattice generation the outline was traced for.
    var tracedDay as Number = -1;
    var tracedFor as Number = -1;

    //! Is the outline current for what `filter()` last chose?
    function traced() as Boolean {
        return shownDay >= 0 && tracedDay == shownDay && tracedFor == shownFor;
    }

    //! Trace the outline if the day or the lattice has moved since.
    //!
    //! **Never from onUpdate.** The trace is cheap on its own and still tipped
    //! the watchdog over on the first version, which ran it inside the same
    //! callback as the full redraw a new day always is. The view calls this
    //! from the wake, show and peek callbacks, each with a budget of its own.
    //! The cost of that is honest and documented: a date that rolls over while
    //! the face is awake draws its dots but not its outline until the next
    //! wake, since nothing calls in between.
    function ensureTraced() as Void {
        if (shownDay >= 0 && !traced()) {
            trace(shownDay);
        }
    }

    //! Trace the outline, all in window-cell space so every step is a lookup.
    //!
    //! The numeral inset by half a pitch is the union of the squares between
    //! the centres of every 2x2 block of numeral cells — at SCALE 2 each font
    //! pixel is one such block. A unit edge between two neighbouring centres
    //! is on the outline exactly when that inset shape lies on one side of it
    //! and not the other. `tools/mockup.py` traces the same edges with the same
    //! rule; `theOutlineMatchesTheMockup` pins the counts together.
    function trace(day as Number) as Void {
        var stride = COLS + 1;
        // inside[(row + 1) * stride + col + 1] is the square whose top-left
        // centre is cell (col, row). Padded by one row and one column so the
        // squares above row 0 and left of column 0 read false with no test.
        var inside = new [(ROWS + 1) * stride] as Array<Boolean>;
        for (var j = 0; j < inside.size(); j++) {
            inside[j] = false;
        }
        var numeral = new [CELLS] as Array<Boolean>;
        for (var row = 0; row < ROWS; row++) {
            for (var col = 0; col < COLS; col++) {
                numeral[row * COLS + col] = cellLit(day, col, row);
            }
        }
        for (var row = 0; row + 1 < ROWS; row++) {
            for (var col = 0; col + 1 < COLS; col++) {
                var c = row * COLS + col;
                inside[(row + 1) * stride + col + 1] =
                    numeral[c] && numeral[c + 1] &&
                    numeral[c + COLS] && numeral[c + COLS + 1];
            }
        }

        // right[c]: an outline edge from cell c to the one right of it;
        // down[c]: to the one below.
        var right = new [CELLS] as Array<Boolean>;
        var down = new [CELLS] as Array<Boolean>;
        for (var row = 0; row < ROWS; row++) {
            for (var col = 0; col < COLS; col++) {
                var c = row * COLS + col;
                var here = inside[(row + 1) * stride + col + 1];
                right[c] = (col + 1 < COLS) &&
                           (inside[row * stride + col + 1] != here);
                down[c] = (row + 1 < ROWS) &&
                          (inside[(row + 1) * stride + col] != here);
            }
        }

        // Breadth first along the edges from each loop's first cell in
        // row-major order — its top-left — so every loop grows from one dot in
        // both directions at once.
        var depth = new [CELLS] as Array<Number>;
        for (var c = 0; c < CELLS; c++) {
            depth[c] = -1;
        }
        var queue = new [CELLS] as Array<Number>;
        var next = new [4] as Array<Number>;
        maxDepth = 0;
        for (var start = 0; start < CELLS; start++) {
            if (depth[start] >= 0) {
                continue;
            }
            var touched = right[start] || down[start] ||
                          (start % COLS > 0 && right[start - 1]) ||
                          (start >= COLS && down[start - COLS]);
            if (!touched) {
                continue;
            }
            depth[start] = 0;
            queue[0] = start;
            var head = 0;
            var tail = 1;
            while (head < tail) {
                var at = queue[head];
                head++;
                next[0] = right[at] ? at + 1 : -1;
                next[1] = down[at] ? at + COLS : -1;
                next[2] = (at % COLS > 0 && right[at - 1]) ? at - 1 : -1;
                next[3] = (at >= COLS && down[at - COLS]) ? at - COLS : -1;
                for (var j = 0; j < 4; j++) {
                    var n = next[j];
                    if (n >= 0 && depth[n] < 0) {
                        depth[n] = depth[at] + 1;
                        if (depth[n] > maxDepth) {
                            maxDepth = depth[n];
                        }
                        queue[tail] = n;
                        tail++;
                    }
                }
            }
        }

        // Cells back to positions in `index`, which is what the colours and
        // the dot coordinates are kept by.
        var kOf = new [CELLS] as Array<Number>;
        for (var k = 0; k < lit; k++) {
            kOf[indexCell[k]] = k;
        }
        if (segA.size() != 2 * CELLS) {
            segA = new [2 * CELLS] as Array<Number>;
            segB = new [2 * CELLS] as Array<Number>;
            segDepth = new [2 * CELLS] as Array<Number>;
            segInked = new [2 * CELLS] as Array<Number>;
        }
        var n = 0;
        for (var c = 0; c < CELLS; c++) {
            if (right[c]) {
                segA[n] = kOf[c];
                segB[n] = kOf[c + 1];
                segDepth[n] = (depth[c] > depth[c + 1]) ? depth[c] : depth[c + 1];
                n++;
            }
            if (down[c]) {
                var below = c + COLS;
                segA[n] = kOf[c];
                segB[n] = kOf[below];
                segDepth[n] = (depth[c] > depth[below]) ? depth[c] : depth[below];
                n++;
            }
        }
        segments = n;
        forgetInk();
        tracedDay = day;
        tracedFor = shownFor;
    }

    //! Say that the buffer no longer holds any of the outline: it was cleared.
    function forgetInk() as Void {
        for (var s = 0; s < segInked.size(); s++) {
            segInked[s] = -1;
        }
    }

    //! Ink the outline as far as `reach` (0.0-1.0) of the way round each loop.
    //!
    //! Called after the renderer, into the same buffer, so the colours it reads
    //! are the ones just drawn. Each line fills the gap between two crosses and
    //! nothing else, and only a clear ever touches those gaps — a ring repaint
    //! draws crosses, a mark's erase blacks one cell. So a segment already
    //! standing in its dot's current colour is skipped, and `cleared` says the
    //! buffer was just blacked and nothing is standing. **Pass true on every
    //! frame the gate cleared**, or the outline vanishes until a dot under it
    //! changes colour.
    function drawContour(dc as Dc, drift as Array<Number>, reach as Float,
                         cleared as Boolean) as Void {
        if (!traced()) {
            return;
        }
        if (cleared) {
            forgetInk();
        }
        inked = 0;
        var cx = (dc.getWidth() / 2) + drift[0];
        var cy = (dc.getHeight() / 2) + drift[1];
        var limit = reach * maxDepth;
        var percent = linePercent();
        var xs = DotGrid.xs;
        var ys = DotGrid.ys;
        var last = -2;
        for (var s = 0; s < segments; s++) {
            if (segDepth[s] > limit) {
                continue;
            }
            var a = segA[s];
            var colour = colours[a];
            if (colour < 0 || colour == segInked[s]) {
                continue;                   //! not drawn yet, or already standing
            }
            segInked[s] = colour;
            inked++;
            if (colour != last) {
                last = colour;
                dc.setColor(dimmed(colour, percent), Graphics.COLOR_TRANSPARENT);
            }
            var i = index[a];
            var j = index[segB[s]];
            var x = cx + xs[i];
            var y = cy + ys[i];
            // fillRectangle, not drawLine: its extent is unambiguous, and a
            // line whose end pixel lands one too far paints the neighbour's
            // arm tip.
            if (ys[i] == ys[j]) {
                var left = (xs[i] < xs[j]) ? x : cx + xs[j];
                dc.fillRectangle(left + GAP_FROM, y, GAP_LENGTH, 1);
            } else {
                var top = (ys[i] < ys[j]) ? y : cy + ys[j];
                dc.fillRectangle(x, top + GAP_FROM, 1, GAP_LENGTH);
            }
        }
    }

    //! A colour at `percent`, channel by channel.
    function dimmed(colour as Number, percent as Number) as Number {
        var r = ((colour >> 16) & 0xFF) * percent / 100;
        var g = ((colour >> 8) & 0xFF) * percent / 100;
        var b = (colour & 0xFF) * percent / 100;
        return (r << 16) | (g << 8) | b;
    }

    //! Is this dot one of the numeral's? The readable definition, used by the tests and by
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
    //! every frame the date is on — including the ones the gate goes on to
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
