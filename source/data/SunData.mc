import Toybox.Complications;
import Toybox.Lang;

//! Today's sunrise and sunset, as positions on the dial. Pure queries, no
//! drawing.
//!
//! **Read from the watch's own Sunrise and Sunset complications**, not from
//! `Weather.getSunrise()`. That call needs a location, and the only one a face
//! can have without asking for GPS — the weather's own
//! `observationLocationPosition` — is documented as null unless the app holds
//! the Positioning permission. The complications are the watch's answer to the
//! same question, already worked out against wherever it last knew it was, and
//! they ask nothing of the manifest.
//!
//! **A sun time sits where the hour hand will point when it happens.** The
//! value is seconds since local midnight, so the position is that time on a
//! twelve-hour dial: sunrise at 06:30 lands at half past six, sunset at 19:45
//! at a quarter to eight. The same anchoring the hour blocks use — the dial
//! the wearer reads the hands against is the scale, and nothing rotates.
//!
//! Today's times rather than the next ones. On a twelve-hour dial tomorrow's
//! sunrise sits a minute or two from today's, under a dot that is several
//! minutes wide, so the distinction would cost a second read for nothing that
//! draws.
//!
//! Sampled once a minute like the weather, and both times from one refresh.
module SunData {

    const SECONDS_PER_DAY = 86400;
    const SECONDS_PER_DIAL = 43200;    //! twelve hours, once round

    var takenAt as Number = 0;
    var sampled as Boolean = false;
    var rise as Float = Source.NO_MARKER;
    var set as Float = Source.NO_MARKER;

    //! Take a fresh sample if the last one has expired.
    function refresh() as Void {
        if (!Sample.due(takenAt, sampled)) {
            return;
        }
        takenAt = Sample.now();
        sampled = true;
        rise = dialOf(read(Complications.COMPLICATION_TYPE_SUNRISE));
        set = dialOf(read(Complications.COMPLICATION_TYPE_SUNSET));
    }

    //! Drop the sample, so the next read goes to the watch. For the tests.
    function forget() as Void {
        sampled = false;
    }

    //! Write [sunrise, sunset] positions into `out` at `at`, either of them
    //! Source.NO_MARKER when the watch has no answer — never synced, or a
    //! polar day or night with no sunrise to report.
    function fill(out as Array<Float>, at as Number) as Void {
        refresh();
        out[at] = rise;
        out[at + 1] = set;
    }

    //! A complication's value, or null when the watch does not have one.
    //!
    //! getComplication() throws rather than returning null for a type the
    //! device does not publish, and a watch face that throws in its frame
    //! preamble is a face that does not load — so the whole read is guarded,
    //! and a missing complication reads exactly like a missing sunrise.
    function read(type as Complications.Type) as Number? {
        if (!(Toybox has :Complications)) {
            return null;
        }
        try {
            var value = Complications.getComplication(
                new Complications.Id(type)).value;
            if (value instanceof Number) {
                return value;
            }
        } catch (ex) {
        }
        return null;
    }

    //! Where a time of day, in seconds since local midnight, sits on the
    //! twelve-hour dial: 0.0 at twelve, turning clockwise, below 1.0. Null and
    //! anything outside a day are no answer.
    //!
    //! The pure half, so the tests can assert it without owning a sunrise.
    function dialOf(seconds as Number?) as Float {
        if (seconds == null || seconds < 0 || seconds >= SECONDS_PER_DAY) {
            return Source.NO_MARKER;
        }
        return (seconds % SECONDS_PER_DIAL).toFloat() / SECONDS_PER_DIAL;
    }
}
