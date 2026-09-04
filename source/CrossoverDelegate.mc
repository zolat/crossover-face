import Toybox.Lang;
import Toybox.WatchUi;

//! Touch-and-hold behavior for watches whose time hands are part of the face.
//!
//! A live watch face cannot take over the Epix's physical buttons. It can
//! receive WatchFaceDelegate.onPress(), which Garmin defines as touch-and-hold.
//! The gesture is therefore a temporary peek rather than another persistent
//! setting: hide the drawn hands now, restore them when the face sleeps.
class CrossoverDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as CrossoverView;

    function initialize(view as CrossoverView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as WatchUi.ClickEvent) as Boolean {
        return _view.togglePeek();
    }
}
