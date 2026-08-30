import Toybox.Lang;

//! Settings and the palette they imply are always reloaded together: which
//! theme the rings carry is itself a setting, so a load without a rebuild
//! leaves the face drawing last session's colours.
//!
//! The order is load-bearing for that reason — StatMap.load() before
//! Palette.build(), never the other way round. (An older comment here claimed
//! the hues came from each ring's *source* assignment. They never did:
//! Palette.build() reads StatMap.RINGS, the count, and never StatMap.rings.)
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
