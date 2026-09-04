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
        // No setting changes the lattice geometry. Rebuilding all 1,112 dots
        // every time the face returns from a menu adds exactly the synchronous
        // work a view transition has to wait for, while producing byte-for-byte
        // identical cache contents. DotGrid starts stale and onLayout builds it
        // once; only an explicit geometry change should invalidate it.
    }
}
