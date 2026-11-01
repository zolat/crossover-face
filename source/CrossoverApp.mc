import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Application entry point. Owns the view's lifecycle and keeps the face in
//! step with the user's settings.
class CrossoverApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        Config.reload();
        // At start too, not only on a phone-side change: a .SET pushed over
        // USB to a sideloaded face is only read when the app starts.
        ConfigCode.sync();
    }

    function onStop(state as Dictionary?) as Void {
    }

    //! Called when the user changes settings in Garmin Connect or Express.
    function onSettingsChanged() as Void {
        // Config.reload() also invalidates the authoritative buffered frame.
        Config.reload();
        // A pasted config code wins over list fields saved alongside it, and
        // either way the code field is rewritten to what the face now draws.
        ConfigCode.sync();
        WatchUi.requestUpdate();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new CrossoverView();
        return [view, new CrossoverDelegate(view)];
    }

    //! The on-device settings menu, offered by the system Watch Face menu.
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return [new SettingsMenu(), new SettingsMenuDelegate()];
    }
}
