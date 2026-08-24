import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Application entry point. Owns nothing but the view's lifecycle.
class CrossoverApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    //! @return the watch face view
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [ new CrossoverView() ];
    }
}
