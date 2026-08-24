import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! On-device layout picker, reached from the watch's own Watch Face menu.
//!
//! Watch faces cannot take input during normal operation; AppBase.getSettingsView()
//! is the sanctioned exception. This matters for a sideloaded face, where the
//! phone-side settings in Garmin Connect are not dependable.
class LayoutMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => Rez.Strings.LayoutTitle});
        addLayout(StatMap.LAYOUT_BANDS_BOTTOM, Rez.Strings.LayoutBandsBottom);
        addLayout(StatMap.LAYOUT_BANDS_CENTRE, Rez.Strings.LayoutBandsCentre);
        addLayout(StatMap.LAYOUT_RINGS, Rez.Strings.LayoutRings);
    }

    //! The active layout carries a sublabel, so the menu shows what is set
    //! rather than making the user remember.
    private function addLayout(layout as Number, label as ResourceId) as Void {
        var subLabel = (StatMap.layout == layout) ? Rez.Strings.LayoutInUse : null;
        addItem(new WatchUi.MenuItem(label, subLabel, layout, null));
    }
}

//! Applies the chosen layout immediately and returns to the watch face.
class LayoutMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var chosen = item.getId();
        if (chosen != null) {
            Properties.setValue(StatMap.PROPERTY_LAYOUT, chosen as Number);
            StatMap.load();
            WatchUi.requestUpdate();
        }
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}
