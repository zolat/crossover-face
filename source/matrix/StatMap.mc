import Toybox.Lang;
import Toybox.Math;

//! Decides which stat a dot belongs to and whether it is filled.
//!
//! This is the seam between the two layouts. Both share the same lattice; only
//! the mapping differs, so switching the face's whole character is one constant.
module StatMap {

    enum Layout {
        LAYOUT_BANDS = 0,       //! Column picks the stat, y picks the fill.
        LAYOUT_RINGS = 1        //! Radius picks the ring, angle picks the fill.
    }

    const LAYOUT = LAYOUT_BANDS;

    const STATS = 4;
    const RING_THICKNESS = (DotGrid.RADIUS - DotGrid.HUB) / STATS;

    //! Classify one dot into a palette slot: stat * 2, plus 1 when filled.
    //! Returning a single packed index lets the renderer look the colour up
    //! directly instead of branching per dot.
    function classify(col as Number, dx as Number, dy as Number,
                      values as Array<Float>) as Number {
        var stat;
        var filled;

        if (LAYOUT == LAYOUT_BANDS) {
            stat = col * STATS / DotGrid.COLS;
            if (stat >= STATS) { stat = STATS - 1; }
            // Waterline measured from the top of the circle downwards.
            var waterline = DotGrid.RADIUS - (values[stat] * 2 * DotGrid.RADIUS);
            filled = dy >= waterline;
        } else {
            var distance = Math.sqrt(dx * dx + dy * dy);
            stat = ((DotGrid.RADIUS - distance) / RING_THICKNESS).toNumber();
            if (stat < 0) { stat = 0; }
            if (stat >= STATS) { stat = STATS - 1; }
            // Degrees clockwise from twelve o'clock.
            var angle = Math.toDegrees(Math.atan2(dx, -dy));
            if (angle < 0) { angle += 360; }
            filled = angle <= values[stat] * 360;
        }

        return stat * 2 + (filled ? 1 : 0);
    }
}
