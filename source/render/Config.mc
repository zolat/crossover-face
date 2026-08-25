import Toybox.Lang;

//! Settings and the palette they imply are always reloaded together: the
//! palette's hues come from whichever source each ring is assigned to, so one
//! without the other leaves the face drawing last session's colours.
module Config {
    function reload() as Void {
        StatMap.load();
        Palette.build();
        // The dot cache depends on the layout, but building it here would run
        // inside onStart, whose watchdog is far tighter than a frame's. Mark
        // it stale and let the renderer rebuild it on the next draw.
        DotGrid.invalidate();
    }
}
