import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

//! The time, drawn as one ring: two fills clockwise from twelve, the hour's
//! and the minute's, whose two ends are where the hands would point. Two
//! styles, which differ only in where each fill may go and what it is painted:
//!
//!   - **split** (SOURCE_TIME): the hour fills the innermost sub-band and the
//!     minute the outer two, both white over the ring's dim tier;
//!   - **overlap** (SOURCE_TIME_OVERLAP): each fills the whole thickness;
//!     where both have passed is the ring's own theme colour, and the hour
//!     and minute are its hue split either way (Palette.timeOverlap), over a
//!     neutral grey.
//!
//! So a dot is in one of four slots — neither, hour, minute, both — and the
//! style is two radius bounds and a four-colour table, settled before the
//! walk. There is no per-dot style test.
//!
//! **Its own module, called once per ring rather than inlined in the dot loop.**
//! MatrixRenderer.drawAt() is already as wide a frame as the test runner's
//! stack can hold, and the span loop must not grow a per-dot test for a ring
//! most faces never have. So drawAt() does everything a ring needs before its
//! loop — the delta key, the mark, the numeral cursor — and hands the walk to
//! this, the way a block ring has a loop of its own.
//!
//! A time ring never shares the screen with hand backing: only a watch with no
//! hands carries one. So there is no hand test here at all.
//!
//! Two extras, each a setting and each Off by default, both solid dots — the
//! face's one way of calling a position out on a field of crosses:
//!
//!   - **hour marks** (StatMap.hourMarks): one dot on the ring's *outer* edge
//!     at each hour, solid in the colour the ring has there, the current
//!     hour's lifted toward white (Palette.HOUR_MARK_TINT). Drawn after the
//!     walk, so every full repaint puts them back; awake and always-on alike.
//!   - **the seconds dot** (StatMap.seconds): one dot on the ring's *inner*
//!     edge where a second hand would point, awake only. It rides the ring's
//!     mark slot (StatMap.fillSecondMark) and MatrixRenderer's mark pass
//!     draws it. A second that moved nothing else is a **tick**: drawAt()
//!     blacks the old cell and asks draw() to repaint that one dot rather
//!     than the ring.
//!
//! Opposite edges so the two never meet: a tick only ever has to repaint a
//! plain cross, never an hour mark (theSecondsDotNeverLandsOnAnHourMark).
module TimeRing {

    //! Slot colours, indexed by slotOf(): neither, hour, minute, both.
    const NEITHER = 0;
    const HOUR = 1;
    const MINUTE = 2;
    const BOTH = 3;

    const HOURS = 12;

    //! Which dot each hour's mark sits on, for `marksRing` at lattice
    //! generation `marksGeneration`. Found once with DotGrid.nearDot() — twelve
    //! small searches — rather than per draw.
    var hourDots as Array<Number> = [] as Array<Number>;
    var marksRing as Number = -1;
    var marksGeneration as Number = -1;

    //! The seconds dot's last answer, so a frame that asks again for the same
    //! second does not search again.
    var secondFor as Float = -2.0;
    var secondAt as Number = -1;
    var secondRing as Number = -1;
    var secondGeneration as Number = -1;

    //! The ring draw() last walked whole with the hour marks on, and what it
    //! was walked with, for drawPendingMarks(). -1 for none.
    var pendingRing as Number = -1;
    var pendingHourEnd as Float = 0.0;
    var pendingMinuteEnd as Float = 0.0;
    var pendingSource as Number = 0;
    var pendingDim as Number = 0;

    //! Walk one ring and paint every dot of it. Never a delta: the print moves
    //! once a minute, and drawAt() keeps the ring out of the delta path.
    //!
    //! `hourEnd` and `minuteEnd` are the ring's span — see Source.SOURCE_TIME.
    //! `dim` is the ring's dim tier, which only the split style draws. The pen
    //! colour is left wherever the last dot set it; the caller forgets its own
    //! cached pen afterwards.
    //!
    //! Returns how many dots it painted — every one in the ring — for the
    //! caller to add to its own count, which it publishes once a draw.
    //!
    //! A second that moved nothing else is not this: it is repaintOne(),
    //! which drawAt() calls in this one's place.
    function draw(dc as Dc, ring as Number, centreX as Number,
                  centreY as Number, hourEnd as Float, minuteEnd as Float,
                  source as Number, dim as Number) as Number {
        var xs = DotGrid.xs;
        var ys = DotGrid.ys;
        var positionOf = DotGrid.positionOf;
        var armOf = DotGrid.armOf;
        var arms = DotGrid.ARMS;
        var turned = (StatMap.rotation == StatMap.ROTATION_RADIAL);
        var ax = arms[0];
        var ay = arms[1];
        var bx = arms[2];
        var by = arms[3];
        var colours = coloursFor(source, dim);
        var hourOut = hourBound(ring, source);
        var minuteIn = minuteBound(ring, source);

        // This ring's slice of the date, as drawAt() seeds it for the others.
        var dating = DateGlyph.active && DateGlyph.lit > 0;
        var glyphIndex = DateGlyph.index;
        var glyphColour = DateGlyph.colours;
        var glyphAt = dating ? DateGlyph.firstFor[ring] : 0;
        var glyphEnd = dating ? DateGlyph.firstFor[ring + 1] : 0;
        var glyphNext = (glyphAt < glyphEnd) ? glyphIndex[glyphAt] : -1;

        var lastColour = -1;
        var last = DotGrid.ringStart[ring + 1];
        for (var i = DotGrid.ringStart[ring]; i < last; i++) {
            var dx = xs[i];
            var dy = ys[i];
            // slotOf(), inlined: this is the loop it defines.
            var radiusSq = dx * dx + dy * dy;
            var position = positionOf[i];
            var slot = (radiusSq <= hourOut && position < hourEnd) ? HOUR
                                                                   : NEITHER;
            if (radiusSq > minuteIn && position < minuteEnd) {
                slot += MINUTE;
            }
            var colour = colours[slot];
            if (colour != lastColour) {
                dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
                lastColour = colour;
            }
            if (i == glyphNext) {
                glyphColour[glyphAt] = colour;
                glyphAt++;
                glyphNext = (glyphAt < glyphEnd) ? glyphIndex[glyphAt] : -1;
                MatrixRenderer.recorded++;
            }
            var x = centreX + dx;
            var y = centreY + dy;
            if (turned) {
                var a = armOf[i];
                ax = arms[a];
                ay = arms[a + 1];
                bx = arms[a + 2];
                by = arms[a + 3];
            }
            dc.drawLine(x - ax, y - ay, x + ax, y + ay);
            dc.drawLine(x - bx, y - by, x + bx, y + by);
        }
        // The hour marks go down after every ring is walked, from drawAt()'s
        // own level: called from here, their placement search sat one frame
        // deeper than the sun dots' and overflowed the test runner's stack.
        if (StatMap.hourMarks == StatMap.TIME_EXTRA_ON) {
            pendingRing = ring;
            pendingHourEnd = hourEnd;
            pendingMinuteEnd = minuteEnd;
            pendingSource = source;
            pendingDim = dim;
        }
        return last - DotGrid.ringStart[ring];
    }

    //! A tick: the one dot the seconds dot has just left, put back as the
    //! cross it is — `at`, whose cell the caller has blacked, or -1 for
    //! nothing. Only asked for when the span is the one the ring was last
    //! drawn with, so every other dot is already right. Returns how many dots
    //! it painted, 0 or 1.
    //!
    //! Called from drawAt() itself rather than through draw(): draw()'s frame
    //! is wide, and with this beneath it the test runner's stack overflowed.
    function repaintOne(dc as Dc, ring as Number, centreX as Number,
                        centreY as Number, hourEnd as Float, minuteEnd as Float,
                        source as Number, dim as Number, at as Number) as Number {
        if (at < 0) {
            return 0;
        }
        var dx = DotGrid.xs[at];
        var dy = DotGrid.ys[at];
        var slot = slotOf(ring, dx, dy, DotGrid.positionOf[at], hourEnd,
                          minuteEnd, source);
        dc.setColor(coloursFor(source, dim)[slot], Graphics.COLOR_TRANSPARENT);
        var arms = DotGrid.ARMS;
        var a = (StatMap.rotation == StatMap.ROTATION_RADIAL) ? DotGrid.armOf[at]
                                                              : 0;
        var x = centreX + dx;
        var y = centreY + dy;
        dc.drawLine(x - arms[a], y - arms[a + 1], x + arms[a], y + arms[a + 1]);
        dc.drawLine(x - arms[a + 2], y - arms[a + 3],
                    x + arms[a + 2], y + arms[a + 3]);
        return 1;
    }

    //! The hour marks of whichever ring draw() walked whole this frame, if
    //! any. MatrixRenderer.drawAt() calls this after its ring loop, beside the
    //! sun dots and before the marks. A tick walks nothing, so it leaves the
    //! marks it did not touch where they are.
    function drawPendingMarks(dc as Dc, centreX as Number,
                              centreY as Number) as Void {
        var ring = pendingRing;
        if (ring < 0) {
            return;
        }
        pendingRing = -1;
        // Found here rather than inside drawHourMarks(): this is the depth the
        // sun dots' search runs at, and one frame deeper overflowed.
        var dots = hourDotsFor(ring);
        drawHourMarks(dc, ring, dots, centreX, centreY, pendingHourEnd,
                      pendingMinuteEnd, pendingSource,
                      coloursFor(pendingSource, pendingDim));
    }

    //! The twelve hour marks, solid, after the walk has put every cross down.
    //! Each takes the colour its dot was just painted, so a mark says nothing
    //! the ring was not already saying — only *where* the hours are. The
    //! current hour — the one the hour's fill last passed — is lifted toward
    //! white.
    //!
    //! In the split style an hour the minute's fill has passed is white
    //! already, which leaves the current hour nothing to be lifted to. It is
    //! still the solid white dot it would have been; only the highlight goes.
    function drawHourMarks(dc as Dc, ring as Number, dots as Array<Number>,
                           centreX as Number, centreY as Number,
                           hourEnd as Float, minuteEnd as Float,
                           source as Number, colours as Array<Number>) as Void {
        var current = currentHour(hourEnd);
        var half = DotGrid.DOT / 2;
        for (var h = 0; h < HOURS; h++) {
            var at = dots[h];
            if (at < 0) {
                continue;
            }
            var dx = DotGrid.xs[at];
            var dy = DotGrid.ys[at];
            var colour = colours[slotOf(ring, dx, dy, DotGrid.positionOf[at],
                                        hourEnd, minuteEnd, source)];
            if (h == current) {
                colour = Palette.mix(Palette.MARKER, colour,
                                     Palette.HOUR_MARK_TINT);
            }
            dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(centreX + dx - half, centreY + dy - half,
                             DotGrid.DOT, DotGrid.DOT);
        }
    }

    //! Which hour's mark is the current one: the last the hour's fill passed.
    //! The nudge is far under the 1/60 of an hour a minute moves it, and only
    //! there so that ten o'clock, whose end is 10/12 in floating point, is not
    //! read as nine.
    function currentHour(hourEnd as Float) as Number {
        return (hourEnd * HOURS + 0.001).toNumber() % HOURS;
    }

    //! The dot each hour's mark sits on: the one nearest the ring's outer edge
    //! inside the hour's window, the way the sunset dot is found. -1 for an
    //! hour no dot answers, which theHourMarksSitOnTheOuterEdge rules out.
    function hourDotsFor(ring as Number) as Array<Number> {
        if (marksRing == ring && marksGeneration == DotGrid.generation &&
                hourDots.size() == HOURS) {
            return hourDots;
        }
        var outer = (ring == 0) ? DotGrid.RADIUS.toFloat()
                                : Math.sqrt(DotGrid.ringEdge[ring - 1]).toFloat();
        var dots = new [HOURS] as Array<Number>;
        for (var h = 0; h < HOURS; h++) {
            dots[h] = DotGrid.nearDot(ring, h.toFloat() / HOURS,
                                      DotGrid.SUN_OUTWARD, outer);
        }
        hourDots = dots;
        marksRing = ring;
        marksGeneration = DotGrid.generation;
        return dots;
    }

    //! The dot the seconds dot sits on at position `at`: the one nearest the
    //! ring's inner edge inside its window, the way the sunrise dot is found.
    //! -1 for Source.NO_MARKER. Remembered, so a frame asking the same second
    //! twice searches once.
    function secondDotFor(ring as Number, at as Float) as Number {
        if (secondFor == at && secondRing == ring &&
                secondGeneration == DotGrid.generation) {
            return secondAt;
        }
        var dot = (at >= 0.0)
            ? DotGrid.nearDot(ring, at, DotGrid.SUN_INWARD,
                              DotGrid.ringInner[ring].toFloat())
            : -1;
        secondFor = at;
        secondAt = dot;
        secondRing = ring;
        secondGeneration = DotGrid.generation;
        return dot;
    }

    //! What each slot is painted, for this style.
    function coloursFor(source as Number, dim as Number) as Array<Number> {
        if (source == Source.SOURCE_TIME_OVERLAP) {
            return Palette.timeOverlap;
        }
        return [dim, Palette.TIME_LIT, Palette.TIME_LIT, Palette.TIME_LIT]
               as Array<Number>;
    }

    //! The squared radius the hour's fill reaches out to. Split, the innermost
    //! sub-band's outer edge — integer, like every edge the block ring reads,
    //! so it agrees with the edges that made the ring. Overlapping, past the
    //! ring, so every dot qualifies.
    function hourBound(ring as Number, source as Number) as Number {
        if (source == Source.SOURCE_TIME_OVERLAP) {
            return DotGrid.RADIUS * DotGrid.RADIUS;
        }
        return DotGrid.bandEdge[ring * HourBands.BANDS];
    }

    //! The squared radius the minute's fill starts beyond: the same edge
    //! split, so the two halves tile the ring; nothing, overlapping.
    function minuteBound(ring as Number, source as Number) as Number {
        if (source == Source.SOURCE_TIME_OVERLAP) {
            return -1;
        }
        return DotGrid.bandEdge[ring * HourBands.BANDS];
    }

    //! Which fills cover the dot at (dx, dy), at this position round its ring:
    //! NEITHER, HOUR, MINUTE or BOTH. The readable definition of the loop
    //! above, for the tests.
    function slotOf(ring as Number, dx as Number, dy as Number,
                    position as Float, hourEnd as Float, minuteEnd as Float,
                    source as Number) as Number {
        var radiusSq = dx * dx + dy * dy;
        var slot = NEITHER;
        if (radiusSq <= hourBound(ring, source) && position < hourEnd) {
            slot += HOUR;
        }
        if (radiusSq > minuteBound(ring, source) && position < minuteEnd) {
            slot += MINUTE;
        }
        return slot;
    }

    //! Is the dot lit at all, in the split style? Split never reaches BOTH —
    //! the bounds tile the ring — so lit is any slot but NEITHER.
    function isLit(ring as Number, dx as Number, dy as Number,
                   position as Float, hourEnd as Float,
                   minuteEnd as Float) as Boolean {
        return slotOf(ring, dx, dy, position, hourEnd, minuteEnd,
                      Source.SOURCE_TIME) != NEITHER;
    }
}
