import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Theme names, in StatMap.Theme order. A module const like SOURCE_LABELS
//! below, because the menu and its picker both need it and a second copy is
//! how the two stop agreeing.
const THEME_LABELS = [
    Rez.Strings.ThemeTerrain,
    Rez.Strings.ThemeActivity,
    Rez.Strings.ThemeFrost,
    Rez.Strings.ThemeLagoon,
    Rez.Strings.ThemeNocturne,
    Rez.Strings.ThemeAlpinist,
    Rez.Strings.ThemeAlpinist4
] as Array<ResourceId>;

//! Source names, in Source.Kind order — every value, including the retired
//! one, so this stays indexable by the enum. What the picker *offers* is
//! Source.OFFERED, which is a different and shorter list.
const SOURCE_LABELS = [
    Rez.Strings.SourceSteps,
    Rez.Strings.SourceRetired,
    Rez.Strings.SourceBattery,
    Rez.Strings.SourceBodyBattery,
    Rez.Strings.SourceTemperature,
    Rez.Strings.SourceRain,
    Rez.Strings.SourceIntensityMinutes,
    Rez.Strings.SourceSeconds,
    Rez.Strings.SourceOff,
    Rez.Strings.SourceRainHours,
    Rez.Strings.SourceUvHours,
    Rez.Strings.SourceBodyBatteryHours
] as Array<ResourceId>;

//! On-device settings, reached from the watch's own Watch Face menu.
//!
//! Watch faces cannot take input during normal operation; AppBase.getSettingsView()
//! is the sanctioned exception. This matters for a sideloaded face, where the
//! phone-side settings in Garmin Connect are not dependable.
class SettingsMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => Rez.Strings.SettingsTitle});
        // The theme leads: it is the largest visual choice on the face.
        addItem(new WatchUi.MenuItem(
            Rez.Strings.ThemeTitle, themeLabel(), :theme, null));
        addItem(new WatchUi.MenuItem(
            Rez.Strings.BackingTitle, backingLabel(), :backing, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.AlwaysOnFillTitle,
            alwaysOnFillLabel(), :alwaysOnFill, null));
        addItem(new WatchUi.MenuItem(
            Rez.Strings.RotationTitle, rotationLabel(), :rotation, null));
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
        setSubLabelOf(0, themeLabel());
        setSubLabelOf(1, backingLabel());
        setSubLabelOf(2, alwaysOnFillLabel());
        setSubLabelOf(3, rotationLabel());
        setSubLabelOf(5, Diagnostics.summary());
    }

    private function setSubLabelOf(index as Number,
                                   label as ResourceId or String) as Void {
        var item = getItem(index);
        if (item != null) {
            item.setSubLabel(label);
        }
    }

    private function themeLabel() as ResourceId {
        return THEME_LABELS[StatMap.theme];
    }

    private function alwaysOnFillLabel() as ResourceId {
        var labels = [Rez.Strings.AlwaysOnFillShown,
                      Rez.Strings.AlwaysOnFillHidden] as Array<ResourceId>;
        return labels[StatMap.alwaysOnFill];
    }

    private function rotationLabel() as ResourceId {
        var labels = [Rez.Strings.RotationRadial,
                      Rez.Strings.RotationUpright,
                      Rez.Strings.RotationUprightDate] as Array<ResourceId>;
        return labels[StatMap.rotation];
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
        if (id == :rings) {
            WatchUi.pushView(new RingMenu(), new RingMenuDelegate(),
                             WatchUi.SLIDE_LEFT);
        } else if (id == :theme) {
            push(new ChoiceMenu(Rez.Strings.ThemeTitle, StatMap.PROPERTY_THEME,
                THEME_LABELS, sequential(THEME_LABELS.size()), StatMap.theme));
        } else if (id == :backing) {
            push(new ChoiceMenu(Rez.Strings.BackingTitle, StatMap.PROPERTY_BACKING,
                [Rez.Strings.BackingOff,
                 Rez.Strings.BackingWhite,
                 Rez.Strings.BackingDark] as Array<ResourceId>,
                sequential(3), StatMap.backing));
        } else if (id == :alwaysOnFill) {
            push(new ChoiceMenu(Rez.Strings.AlwaysOnFillTitle,
                StatMap.PROPERTY_ALWAYS_ON_FILL,
                [Rez.Strings.AlwaysOnFillShown,
                 Rez.Strings.AlwaysOnFillHidden] as Array<ResourceId>,
                sequential(2), StatMap.alwaysOnFill));
        } else if (id == :rotation) {
            push(new ChoiceMenu(Rez.Strings.RotationTitle,
                StatMap.PROPERTY_ROTATION,
                [Rez.Strings.RotationRadial,
                 Rez.Strings.RotationUpright,
                 Rez.Strings.RotationUprightDate] as Array<ResourceId>,
                sequential(3), StatMap.rotation));
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

//! Lists the four rings, outermost first, each showing what it is currently
//! assigned to.
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
                               offeredLabelsFor(index),
                               Source.offeredFor(index),
                               StatMap.rings[index]),
                new ChoiceMenuDelegate(), WatchUi.SLIDE_LEFT);
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

//! Values 0..count-1, for the settings whose every value is still offered.
//! Only the ring picker has a gap in it.
function sequential(count as Number) as Array<Number> {
    var out = new [count] as Array<Number>;
    for (var i = 0; i < count; i++) {
        out[i] = i;
    }
    return out;
}

//! The labels for the sources *this ring* may be assigned to, in picker order.
//!
//! Per ring rather than global, because the hourly forecast needs more dots per
//! hour than the inner two rings have. Built from Source.offeredFor() so the
//! labels and the values it is handed beside cannot come out of step — a picker
//! whose two lists disagree stores the wrong source with no symptom at all.
function offeredLabelsFor(ring as Number) as Array<ResourceId> {
    var offered = Source.offeredFor(ring);
    var out = new [offered.size()] as Array<ResourceId>;
    for (var i = 0; i < offered.size(); i++) {
        out[i] = SOURCE_LABELS[offered[i]];
    }
    return out;
}

//! A list of mutually exclusive values for one numeric property.
//!
//! The stored value used to be the item's position, which held for as long as
//! every enum value was offered. It stopped holding when a source was retired:
//! a picker that skips a value can no longer use its own indices, or every
//! source after the gap would be stored as its neighbour. So the values travel
//! beside the labels, and the position is nothing but a position.
class ChoiceMenu extends WatchUi.Menu2 {

    private var _property as String;

    function initialize(title as ResourceId, property as String,
                        labels as Array<ResourceId>, values as Array<Number>,
                        current as Number) {
        Menu2.initialize({:title => title});
        _property = property;
        for (var i = 0; i < labels.size(); i++) {
            var value = values[i];
            var subLabel = (value == current) ? Rez.Strings.InUse : null;
            addItem(new WatchUi.MenuItem(labels[i], subLabel, value, null));
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
