import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Source names, in Source.Kind order.
const SOURCE_LABELS = [
    Rez.Strings.SourceSteps,
    Rez.Strings.SourceHeartRate,
    Rez.Strings.SourceBattery,
    Rez.Strings.SourceBodyBattery,
    Rez.Strings.SourceTemperature,
    Rez.Strings.SourceRain,
    Rez.Strings.SourceOff
] as Array<ResourceId>;

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
        addItem(new WatchUi.MenuItem(Rez.Strings.RingsTitle, null, :rings, null));
        addItem(new WatchUi.MenuItem(
            Rez.Strings.DiagnosticsTitle, Diagnostics.summary(),
            :diagnostics, null));
    }

    //! Sub-labels are built from the current settings, so they go stale the
    //! moment a sub-menu changes one. onShow() runs when this menu returns to
    //! the foreground after that sub-menu is popped, which is the only point
    //! the values can be refreshed — the menu itself is not rebuilt.
    function onShow() as Void {
        Menu2.onShow();
        setSubLabelOf(0, layoutLabel());
        setSubLabelOf(1, backingLabel());
        setSubLabelOf(3, Diagnostics.summary());
    }

    private function setSubLabelOf(index as Number,
                                   label as ResourceId or String) as Void {
        var item = getItem(index);
        if (item != null) {
            item.setSubLabel(label);
        }
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
        } else if (id == :rings) {
            WatchUi.pushView(new RingMenu(), new RingMenuDelegate(),
                             WatchUi.SLIDE_LEFT);
        } else if (id == :backing) {
            push(new ChoiceMenu(Rez.Strings.BackingTitle, StatMap.PROPERTY_BACKING,
                [Rez.Strings.BackingOff,
                 Rez.Strings.BackingWhite,
                 Rez.Strings.BackingDark] as Array<ResourceId>,
                StatMap.backing));
        } else if (id == :diagnostics) {
            // Nothing to open — re-reading it is the useful action, since the
            // figure moves while you are looking at it.
            item.setSubLabel(Diagnostics.summary());
            WatchUi.requestUpdate();
        }
    }

    private function push(menu as ChoiceMenu) as Void {
        WatchUi.pushView(menu, new ChoiceMenuDelegate(), WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}

//! Lists the four rings, each showing what it is currently assigned to.
class RingMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => Rez.Strings.RingsTitle});
        var titles = [Rez.Strings.Ring1Title, Rez.Strings.Ring2Title,
                      Rez.Strings.Ring3Title, Rez.Strings.Ring4Title]
                     as Array<ResourceId>;
        for (var i = 0; i < StatMap.RINGS; i++) {
            addItem(new WatchUi.MenuItem(
                titles[i], SOURCE_LABELS[StatMap.rings[i]], i, null));
        }
    }

    //! See SettingsMenu.onShow() — same staleness, same fix.
    function onShow() as Void {
        Menu2.onShow();
        for (var i = 0; i < StatMap.RINGS; i++) {
            var item = getItem(i);
            if (item != null) {
                item.setSubLabel(SOURCE_LABELS[StatMap.rings[i]]);
            }
        }
    }
}

//! Opens a source picker for whichever ring was chosen.
class RingMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var ring = item.getId();
        if (ring != null) {
            var index = ring as Number;
            WatchUi.pushView(
                new ChoiceMenu(Rez.Strings.RingsTitle,
                               StatMap.PROPERTY_RINGS[index],
                               SOURCE_LABELS, StatMap.rings[index]),
                new ChoiceMenuDelegate(), WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
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
            Config.reload();
            WatchUi.requestUpdate();
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
