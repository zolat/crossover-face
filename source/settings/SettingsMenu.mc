import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Theme names, in StatMap.Theme order. A module const like SOURCE_LABELS
//! below, because the menu and its picker both need it and a second copy is
//! how the two stop agreeing.
const THEME_LABELS = [
    Rez.Strings.ThemeTerrain,
    Rez.Strings.ThemeActivity,
    Rez.Strings.ThemeBeacon,
    Rez.Strings.ThemePulse
] as Array<ResourceId>;

//! Date outline levels, in StatMap.DateOutline order. Shared by the row's
//! sub-label and its picker for the reason THEME_LABELS is.
const DATE_OUTLINE_LABELS = [
    Rez.Strings.DateOutline50,
    Rez.Strings.DateOutline65,
    Rez.Strings.DateOutline80
] as Array<ResourceId>;

//! Always-on brightness, in StatMap.AlwaysOnBoost order. Shared by the row's
//! sub-label and its picker for the reason THEME_LABELS is.
const BOOST_LABELS = [
    Rez.Strings.BoostOff,
    Rez.Strings.BoostBright,
    Rez.Strings.BoostBrightest
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
    Rez.Strings.SourceBodyBatteryHours,
    Rez.Strings.SourceTempHours,
    Rez.Strings.SourceTempSun,
    Rez.Strings.SourceTime,
    Rez.Strings.SourceTimeOverlap
] as Array<ResourceId>;

//! On-device settings, reached from the watch's own Watch Face menu.
//!
//! Watch faces do not receive ordinary button input during normal operation.
//! AppBase.getSettingsView() is the sanctioned persistent-settings surface;
//! the Epix's WatchFaceDelegate touch-and-hold is deliberately transient.
//! This menu matters for a sideloaded face, where phone-side settings in
//! Garmin Connect are not dependable.
class SettingsMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => Rez.Strings.SettingsTitle});
        addItem(new WatchUi.MenuItem(
            Rez.Strings.VersionTitle, BuildInfo.VERSION, :version, null));
        // Version leads so a sideload can be identified without opening or
        // changing any setting; the theme remains the first visual choice.
        addItem(new WatchUi.MenuItem(
            Rez.Strings.ThemeTitle, themeLabel(), :theme, null));
        // Only where there are hands to light the dots behind.
        if (HandStyle.HANDS) {
            addItem(new WatchUi.MenuItem(
                Rez.Strings.BackingTitle, backingLabel(), :backing, null));
        }
        addItem(new WatchUi.MenuItem(Rez.Strings.AlwaysOnFillTitle,
            alwaysOnFillLabel(), :alwaysOnFill, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.BoostTitle,
            BOOST_LABELS[StatMap.boost], :boost, null));
        addItem(new WatchUi.MenuItem(
            Rez.Strings.RotationTitle, rotationLabel(), :rotation, null));
        addItem(new WatchUi.MenuItem(
            Rez.Strings.DateTitle, dateLabel(), :date, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.DateOutlineTitle,
            dateOutlineLabel(), :dateOutline, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.RingsTitle, null, :rings, null));
        addItem(new WatchUi.MenuItem(
            Rez.Strings.DiagnosticsTitle, Diagnostics.summary(),
            :diagnostics, null));
    }

    //! Sub-labels are built from the current settings, so they go stale the
    //! moment a sub-menu changes one. onShow() runs when this menu returns to
    //! the foreground after that sub-menu is popped, which is the only point
    //! the values can be refreshed — the menu itself is not rebuilt.
    //!
    //! **By id, not by row.** Rows used to be refreshed by index, and the Hands
    //! row exists only on a watch with hands, so every row below it sits one
    //! place higher on the Epix than on the Crossover. An index refresh would
    //! label each with its neighbour's value, and getItem() on a wrong index
    //! answers null rather than throwing.
    function onShow() as Void {
        Menu2.onShow();
        setSubLabelOf(:theme, themeLabel());
        if (HandStyle.HANDS) {
            setSubLabelOf(:backing, backingLabel());
        }
        setSubLabelOf(:alwaysOnFill, alwaysOnFillLabel());
        setSubLabelOf(:boost, BOOST_LABELS[StatMap.boost]);
        setSubLabelOf(:rotation, rotationLabel());
        setSubLabelOf(:date, dateLabel());
        setSubLabelOf(:dateOutline, dateOutlineLabel());
        setSubLabelOf(:diagnostics, Diagnostics.summary());
    }

    private function setSubLabelOf(id as Symbol,
                                   label as ResourceId or String) as Void {
        var index = findItemById(id);
        if (index < 0) {
            return;
        }
        var item = getItem(index);
        if (item != null) {
            item.setSubLabel(label);
        }
    }

    private function themeLabel() as ResourceId {
        return themeLabelFor(StatMap.theme);
    }

    private function alwaysOnFillLabel() as ResourceId {
        var labels = [Rez.Strings.AlwaysOnFillShown,
                      Rez.Strings.AlwaysOnFillHidden] as Array<ResourceId>;
        return labels[StatMap.alwaysOnFill];
    }

    //! StatMap.load() reads the retired third value as Upright, so two labels
    //! cover every value `rotation` can hold.
    private function rotationLabel() as ResourceId {
        var labels = [Rez.Strings.RotationRadial,
                      Rez.Strings.RotationUpright] as Array<ResourceId>;
        return labels[StatMap.rotation];
    }

    private function dateOutlineLabel() as ResourceId {
        return DATE_OUTLINE_LABELS[StatMap.dateOutline];
    }

    private function dateLabel() as ResourceId {
        var labels = [Rez.Strings.DateOff,
                      Rez.Strings.DateOn] as Array<ResourceId>;
        return labels[StatMap.date];
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
                themeChoiceLabels(), themeChoiceValues(), StatMap.theme));
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
        } else if (id == :boost) {
            push(new ChoiceMenu(Rez.Strings.BoostTitle, StatMap.PROPERTY_BOOST,
                BOOST_LABELS, sequential(3), StatMap.boost));
        } else if (id == :rotation) {
            push(new ChoiceMenu(Rez.Strings.RotationTitle,
                StatMap.PROPERTY_ROTATION,
                [Rez.Strings.RotationRadial,
                 Rez.Strings.RotationUpright] as Array<ResourceId>,
                sequential(2), StatMap.rotation));
        } else if (id == :date) {
            push(new ChoiceMenu(Rez.Strings.DateTitle, StatMap.PROPERTY_DATE,
                [Rez.Strings.DateOff,
                 Rez.Strings.DateOn] as Array<ResourceId>,
                sequential(2), StatMap.date));
        } else if (id == :dateOutline) {
            push(new ChoiceMenu(Rez.Strings.DateOutlineTitle,
                StatMap.PROPERTY_DATE_OUTLINE, DATE_OUTLINE_LABELS,
                sequential(3), StatMap.dateOutline));
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

//! Row indices of RingMenu's two scale rows. Module consts rather than class
//! ones so the tests can name them. RingMenuDelegate tells them from a ring by
//! id, not by position.
const TEMP_LOW_ROW = StatMap.RINGS;
const TEMP_HIGH_ROW = StatMap.RINGS + 1;

//! Lists the four rings, outermost first, each showing what it is currently
//! assigned to, then the two ends of the temperature-ahead scale.
//!
//! The scale rows sit *after* the rings so the rings keep their indices,
//! which double as their item ids and as the index onShow() refreshes.
class RingMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => Rez.Strings.RingsTitle});
        // The last ring is the inner one, whichever it is: ring 4 says so on a
        // four-ring watch and ring 5 on the 454.
        var titles = (StatMap.RINGS == 5)
            ? [Rez.Strings.Ring1Title, Rez.Strings.Ring2Title,
               Rez.Strings.Ring3Title, Rez.Strings.Ring4MiddleTitle,
               Rez.Strings.Ring5Title] as Array<ResourceId>
            : [Rez.Strings.Ring1Title, Rez.Strings.Ring2Title,
               Rez.Strings.Ring3Title, Rez.Strings.Ring4Title]
              as Array<ResourceId>;
        for (var i = 0; i < StatMap.RINGS; i++) {
            addItem(new WatchUi.MenuItem(
                titles[i], SOURCE_LABELS[StatMap.rings[i]], i, null));
        }
        addItem(new WatchUi.MenuItem(Rez.Strings.TempAheadLowTitle,
            celsiusLabel(StatMap.tempAheadLow), :tempAheadLow, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.TempAheadHighTitle,
            celsiusLabel(StatMap.tempAheadHigh), :tempAheadHigh, null));
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
        // The normalised values, so an inverted pair entered on the phone
        // reads back the way round it is drawn.
        var low = getItem(TEMP_LOW_ROW);
        if (low != null) {
            low.setSubLabel(celsiusLabel(StatMap.tempAheadLow));
        }
        var high = getItem(TEMP_HIGH_ROW);
        if (high != null) {
            high.setSubLabel(celsiusLabel(StatMap.tempAheadHigh));
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
        // The scale rows carry Symbol ids. Tested before the ring branch,
        // whose cast to Number would let a Symbol through to an array index.
        if (ring == :tempAheadLow) {
            pushTemperature(Rez.Strings.TempAheadLowTitle,
                StatMap.PROPERTY_TEMP_AHEAD_LOW, StatMap.tempAheadLow);
        } else if (ring == :tempAheadHigh) {
            pushTemperature(Rez.Strings.TempAheadHighTitle,
                StatMap.PROPERTY_TEMP_AHEAD_HIGH, StatMap.tempAheadHigh);
        } else if (ring instanceof Number) {
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

    private function pushTemperature(title as ResourceId, property as String,
                                     current as Number) as Void {
        WatchUi.pushView(temperatureMenu(title, property, current),
                         new ChoiceMenuDelegate(), WatchUi.SLIDE_LEFT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

//! A whole degree as the menus show it.
function celsiusLabel(celsius as Number) as String {
    return celsius.format("%d") + "°C";
}

//! A picker for one end of the temperature-ahead scale: every whole degree the
//! setting allows, coldest first, opening on the value in use so a nudge of a
//! degree or two is a couple of presses rather than a scroll from -20.
function temperatureMenu(title as ResourceId, property as String,
                         current as Number) as ChoiceMenu {
    var count = StatMap.TEMP_AHEAD_MAX_C - StatMap.TEMP_AHEAD_MIN_C + 1;
    var labels = new [count] as Array<String>;
    var values = new [count] as Array<Number>;
    for (var i = 0; i < count; i++) {
        var celsius = StatMap.TEMP_AHEAD_MIN_C + i;
        values[i] = celsius;
        labels[i] = celsiusLabel(celsius);
    }
    return new ChoiceMenu(title, property, labels, values, current);
}

//! The theme picker offers every shipping theme and then Custom, which takes
//! whatever four colours a config code last delivered — Terrain's until one
//! has. Built here rather than stored, because THEME_LABELS and THEME_IDS are
//! the *shipping* lists the palette tables are sized by, and Custom is not in
//! those tables.
function themeChoiceValues() as Array<Number> {
    var values = StatMap.THEME_IDS.slice(0, null);
    values.add(StatMap.THEME_CUSTOM);
    return values;
}

function themeChoiceLabels() as Array<ResourceId> {
    var labels = THEME_LABELS.slice(0, null);
    labels.add(Rez.Strings.ThemeCustom);
    return labels;
}

function themeLabelFor(theme as Number) as ResourceId {
    return (theme == StatMap.THEME_CUSTOM)
        ? Rez.Strings.ThemeCustom
        : THEME_LABELS[StatMap.themeIndex(theme)];
}

//! Values 0..count-1, for contiguous settings whose every value is offered.
//! Themes and ring sources use explicit arrays because their stored IDs have
//! retired gaps.
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
//! hour than the innermost ring has. Built from Source.offeredFor() so the
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
//!
//! It opens focused on the value in use. That costs nothing on a three-row
//! list and is what makes the 71-row temperature list usable.
class ChoiceMenu extends WatchUi.Menu2 {

    private var _property as String;
    private var _focus as Number = 0;

    function initialize(title as ResourceId, property as String,
                        labels as Array<ResourceId> or Array<String>,
                        values as Array<Number>, current as Number) {
        Menu2.initialize({:title => title});
        _property = property;
        for (var i = 0; i < labels.size(); i++) {
            var value = values[i];
            var subLabel = null;
            if (value == current) {
                subLabel = Rez.Strings.InUse;
                _focus = i;
            }
            addItem(new WatchUi.MenuItem(labels[i], subLabel, value, null));
        }
        setFocus(_focus);
    }

    function property() as String {
        return _property;
    }

    //! The row it opened on. Menu2 has no getter for its own focus.
    function focus() as Number {
        return _focus;
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
            // Keep the code field in step, so Garmin Connect shows this change.
            ConfigCode.publish();
            WatchUi.requestUpdate();
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}
