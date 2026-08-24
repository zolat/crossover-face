import Toybox.Lang;

//! Settings and the palette they imply are always reloaded together: the
//! palette's hues come from whichever source each ring is assigned to, so one
//! without the other leaves the face drawing last session's colours.
module Config {
    function reload() as Void {
        StatMap.load();
        Palette.build();
    }
}
