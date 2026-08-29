import Toybox.Lang;

//! Decides whether a frame is worth drawing at all.
//!
//! Awake, the system asks for a frame every second. The face has no second
//! hand and the hands themselves are physical, so almost every one of those
//! frames is pixel-for-pixel the frame before it: steps, heart rate and
//! battery move slowly, and the burn-in drift shifts only every two minutes.
//! Drawing ~1100 dots to reproduce an identical image is the single largest
//! avoidable cost the face has.
//!
//! So each frame is fingerprinted, and an unchanged fingerprint skips the draw.
//! Three things keep that safe:
//!
//!   - **never in always-on.** There the system asks once a minute, so there is
//!     nothing worth saving, and it is the mode whose compositing is least
//!     predictable. Skipping is an awake-only optimisation;
//!   - **a cap on consecutive skips.** Anything that damages the frame buffer
//!     from outside — a notification banner, a system alert — is repaired by
//!     the next draw. Without a cap, a skip would leave that damage on screen
//!     indefinitely; with one, it is gone within a few seconds;
//!   - **an explicit forget().** Coming back from sleep, from the settings menu
//!     or from a settings change, the next frame is always drawn.
//!
//! The fingerprint is compared value by value rather than hashed. A hash
//! collision here would freeze a stale frame until the cap fired, and the
//! comparison is a dozen floats — far cheaper than the draw it guards.
//!
//! One source defeats all of this on purpose. A ring assigned to seconds moves
//! its span every tick, so the fingerprint differs every second and the gate
//! opens every second — the skip percentage in the diagnostics readout drops to
//! roughly nothing. That is not a fault: it is the face drawing at exactly the
//! rate it drew at before this module existed, which is why it stays inside the
//! watchdog. It is a battery cost, and it is the cost of asking for a second
//! hand; nothing here needs changing to accommodate it.
module FrameGate {

    //! Draw at least this often regardless, so anything drawn over the face
    //! from outside is repaired within a few seconds rather than persisting.
    const MAX_SKIPS = 5;

    var skipped as Number = 0;          //! consecutive frames skipped
    var drawn as Number = 0;
    var suppressed as Number = 0;       //! total skipped, for the diagnostics

    var _last as Array<Float>? = null;

    //! True when this frame differs from the last one drawn, or when enough
    //! frames have been skipped that one is due anyway.
    function shouldDraw(fingerprint as Array<Float>) as Boolean {
        var previous = _last;
        if (previous != null && skipped < MAX_SKIPS && same(previous, fingerprint)) {
            skipped++;
            suppressed++;
            return false;
        }
        _last = fingerprint;
        skipped = 0;
        drawn++;
        return true;
    }

    //! Force the next frame to be drawn. Anything that can change the face
    //! without changing the fingerprint has to say so here.
    function forget() as Void {
        _last = null;
        skipped = 0;
    }

    //! Element-wise, because a hash collision would freeze a stale frame.
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

    //! Share of frames that needed no drawing at all.
    function skipPercent() as Number {
        var total = drawn + suppressed;
        return (total == 0) ? 0 : (suppressed * 100) / total;
    }
}
