import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! On-device settings, reached from the watch's own Watch Face menu.
//!
//! Watch faces cannot take input during normal operation; AppBase.getSettingsView()
//! is the sanctioned exception. This matters for a sideloaded face, where the
//! phone-side settings in Garmin Connect are not dependable.
class SettingsMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => Rez.Strings.SettingsTitle});
        addItem(new WatchUi.MenuItem(
            Rez.Strings.LayoutTitle, layoutLabel(), :layout, null));
        addItem(new WatchUi.MenuItem(
            Rez.Strings.BackingTitle, backingLabel(), :backing, null));
    }

    private function layoutLabel() as ResourceId {
        var labels = [Rez.Strings.LayoutBandsBottom,
                      Rez.Strings.LayoutBandsCentre,
                      Rez.Strings.LayoutRings] as Array<ResourceId>;
        return labels[StatMap.layout];
    }

    private function backingLabel() as ResourceId {
        var labels = [Rez.Strings.BackingOff,
                      Rez.Strings.BackingWhite,
                      Rez.Strings.BackingDark] as Array<ResourceId>;
        return labels[StatMap.backing];
    }
}

//! Opens the sub-menu for whichever setting was chosen.
class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :layout) {
            push(new ChoiceMenu(Rez.Strings.LayoutTitle, StatMap.PROPERTY_LAYOUT,
                [Rez.Strings.LayoutBandsBottom,
                 Rez.Strings.LayoutBandsCentre,
                 Rez.Strings.LayoutRings] as Array<ResourceId>,
                StatMap.layout));
        } else if (id == :backing) {
            push(new ChoiceMenu(Rez.Strings.BackingTitle, StatMap.PROPERTY_BACKING,
                [Rez.Strings.BackingOff,
                 Rez.Strings.BackingWhite,
                 Rez.Strings.BackingDark] as Array<ResourceId>,
                StatMap.backing));
        }
    }

    private function push(menu as ChoiceMenu) as Void {
        WatchUi.pushView(menu, new ChoiceMenuDelegate(), WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}

//! A list of mutually exclusive values for one numeric property. The value
//! stored is the item's index, which is why StatMap's enums start at zero and
//! stay in step with resources/settings/settings.xml.
class ChoiceMenu extends WatchUi.Menu2 {

    private var _property as String;

    function initialize(title as ResourceId, property as String,
                        labels as Array<ResourceId>, current as Number) {
        Menu2.initialize({:title => title});
        _property = property;
        for (var i = 0; i < labels.size(); i++) {
            var subLabel = (i == current) ? Rez.Strings.InUse : null;
            addItem(new WatchUi.MenuItem(labels[i], subLabel, i, null));
        }
    }

    function property() as String {
        return _property;
    }
}

//! Applies a choice immediately and returns to the settings menu.
class ChoiceMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var view = WatchUi.getCurrentView()[0];
        var chosen = item.getId();
        if (view instanceof ChoiceMenu && chosen != null) {
            Properties.setValue(view.property(), chosen as Number);
            StatMap.load();
            WatchUi.requestUpdate();
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
