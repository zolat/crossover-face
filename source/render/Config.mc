import Toybox.Lang;

//! Settings and the palette they imply are always reloaded together: the
//! palette's hues come from whichever source each ring is assigned to, so one
//! without the other leaves the face drawing last session's colours.
module Config {
    function reload() as Void {
        StatMap.load();
        Palette.build();
        // Nothing settable moves the lattice any more, but the cache is still
        // dropped here rather than trusted: building it is the one piece of
        // work that must not run inside onStart, whose watchdog is far tighter
        // than a view's and which tripped it outright. Mark the cache stale;
        // onLayout builds it, and the renderer catches any path that skipped
        // onLayout.
        DotGrid.invalidate();
    }
}
