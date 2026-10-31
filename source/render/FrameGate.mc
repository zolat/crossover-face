import Toybox.Lang;

//! Plans changes to the face's authoritative buffered frame.
//!
//! The screen Dc supplied to onUpdate is deliberately absent from this
//! contract. Physical AMOLED firmware can supply a cleared surface during a
//! transition, so "unchanged" cannot safely mean "draw nothing to the screen".
//! CrossoverView instead keeps the complete face in one BufferedBitmap and
//! explicitly presents it on every screen update and animation callback.
//!
//! This module only decides whether that buffer's pixels need changing:
//!
//!   - the **field** print covers changes that move or recolour every dot;
//!   - one **ring** print per ring covers data that can be repainted locally.
//!
//! There is one authoritative surface, so a change is written once. There are
//! no inferred front/back buffers, held duplicate draws, periodic damage
//! repairs or lifecycle timing windows. System overlays never modify the
//! off-screen buffer itself.
module FrameGate {

    var skipped as Number = 0;          //! consecutive unchanged callbacks
    var drawn as Number = 0;            //! successfully committed buffer draws
    var suppressed as Number = 0;       //! total unchanged callbacks

    //! Which rings the pending buffer update must draw, and whether it must
    //! clear the buffer first. Read immediately after plan() returns true.
    var dirty as Array<Boolean> = new [StatMap.RINGS] as Array<Boolean>;
    var clears as Boolean = true;

    //! Last state successfully rendered into the buffer. A pending plan never
    //! changes these; commit() does that only after rendering completes.
    var _field as Array<Float>? = null;
    var _rings as Array<Float>? = null;
    var _forceFull as Boolean = true;

    //! Values per ring in the ring print: span start, span end, mark, over,
    //! the block channel's three packed words, then sunrise and sunset.
    const PER_RING = 9;

    //! Plan an update against the last frame known to be in the buffer.
    //!
    //! True means the caller must render `dirty` and then call commit(). False
    //! means the buffer is already complete and only needs presenting.
    function plan(field as Array<Float>, rings as Array<Float>) as Boolean {
        var previousField = _field;
        var full = _forceFull || previousField == null ||
                   !same(previousField, field);
        clears = full;

        var previousRings = _rings;
        var anything = false;
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            dirty[ring] = full || previousRings == null ||
                          ringMoved(previousRings, rings, ring);
            if (dirty[ring]) {
                anything = true;
            }
        }

        if (!anything) {
            skipped++;
            suppressed++;
        }
        return anything;
    }

    //! Record a plan only after its pixels are safely in the buffer.
    function commit(field as Array<Float>, rings as Array<Float>) as Void {
        _field = copy(field, _field);
        _rings = copy(rings, _rings);
        _forceFull = false;
        skipped = 0;
        drawn++;
    }

    //! Every ring, cleared and redrawn. Used by focused renderer tests and by
    //! callers that already know the old surface cannot be retained.
    function everything() as Array<Boolean> {
        for (var ring = 0; ring < StatMap.RINGS; ring++) {
            dirty[ring] = true;
        }
        clears = true;
        return dirty;
    }

    //! Invalidate buffer contents after a visual configuration or geometry
    //! change. The next successful update will define the complete surface.
    function forget() as Void {
        _forceFull = true;
        skipped = 0;
    }

    //! Has this ring's slice of the print moved?
    function ringMoved(previous as Array<Float>, current as Array<Float>,
                       ring as Number) as Boolean {
        var at = ring * PER_RING;
        for (var i = 0; i < PER_RING; i++) {
            if (previous[at + i] != current[at + i]) {
                return true;
            }
        }
        return false;
    }

    //! Element-wise, because a hash collision would freeze a stale ring.
    function same(a as Array<Float>, b as Array<Float>) as Boolean {
        if (a.size() != b.size()) {
            return false;
        }
        for (var i = 0; i < a.size(); i++) {
            if (a[i] != b[i]) {
                return false;
            }
        }
        return true;
    }

    //! Keep values rather than the caller's reusable arrays.
    function copy(from as Array<Float>, into as Array<Float>?) as Array<Float> {
        var out = into;
        if (out == null || out.size() != from.size()) {
            out = new [from.size()] as Array<Float>;
        }
        for (var i = 0; i < from.size(); i++) {
            out[i] = from[i];
        }
        return out;
    }

    //! Share of callbacks that needed no buffer mutation.
    function skipPercent() as Number {
        var total = drawn + suppressed;
        return (total == 0) ? 0 : (suppressed * 100) / total;
    }
}
