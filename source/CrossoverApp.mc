import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Application entry point. Owns the view's lifecycle and keeps the layout
//! choice in step with the user's settings.
class CrossoverApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        StatMap.load();
    }

    function onStop(state as Dictionary?) as Void {
    }

    //! Called when the user changes settings in Garmin Connect or Express.
    function onSettingsChanged() as Void {
        StatMap.load();
        WatchUi.requestUpdate();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new CrossoverView()];
    }

    //! The on-device settings menu, offered by the system Watch Face menu.
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return [new LayoutMenu(), new LayoutMenuDelegate()];
    }
}
