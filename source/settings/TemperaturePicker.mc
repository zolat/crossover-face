import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! How many whole degrees one end of the temperature-ahead scale may take.
const TEMP_AHEAD_CHOICES = StatMap.TEMP_AHEAD_MAX_C - StatMap.TEMP_AHEAD_MIN_C + 1;

//! Every whole degree the temperature-ahead scale allows, coldest first, made
//! one row at a time as the picker scrolls.
//!
//! This used to be a 71-row Menu2, and Menu2 holds every row it is given:
//! ~12.7KB of heap the moment it opened. On the 51mm the face already sits at
//! ~118KB of its 123.8KB with the ring menu open, so the list ran out of
//! memory before it drew. A factory holds no rows at all; the picker asks for
//! the few on screen.
class TemperatureFactory extends WatchUi.PickerFactory {

    function initialize() {
        PickerFactory.initialize();
    }

    function getSize() as Number {
        return TEMP_AHEAD_CHOICES;
    }

    function getValue(index as Number) as Object? {
        return StatMap.TEMP_AHEAD_MIN_C + index;
    }

    function getDrawable(index as Number, isSelected as Boolean)
            as WatchUi.Drawable? {
        return new WatchUi.Text({
            :text => celsiusLabel(StatMap.TEMP_AHEAD_MIN_C + index),
            :color => Graphics.COLOR_WHITE,
            :font => Graphics.FONT_MEDIUM,
            :locX => WatchUi.LAYOUT_HALIGN_CENTER,
            :locY => WatchUi.LAYOUT_VALIGN_CENTER
        });
    }
}

//! A picker for one end of the temperature-ahead scale, opening on the value
//! in use so a nudge of a degree or two is a couple of presses rather than a
//! scroll from -20.
class TemperaturePicker extends WatchUi.Picker {

    private var _property as String;
    private var _focus as Number;

    function initialize(title as ResourceId, property as String,
                        current as Number) {
        _property = property;
        _focus = temperatureIndexOf(current);
        Picker.initialize({
            :title => new WatchUi.Text({
                :text => WatchUi.loadResource(title) as String,
                :color => Graphics.COLOR_WHITE,
                :font => Graphics.FONT_SMALL,
                :locX => WatchUi.LAYOUT_HALIGN_CENTER,
                :locY => WatchUi.LAYOUT_VALIGN_BOTTOM
            }),
            :pattern => [new TemperatureFactory()]
                as Array<WatchUi.PickerFactory or WatchUi.Drawable>,
            :defaults => [_focus] as Array<Number>
        });
    }

    function property() as String {
        return _property;
    }

    //! The row it opened on. Picker has no getter for its own selection.
    function focus() as Number {
        return _focus;
    }
}

//! The factory row holding a degree, clamped into the scale.
function temperatureIndexOf(celsius as Number) as Number {
    var index = celsius - StatMap.TEMP_AHEAD_MIN_C;
    if (index < 0) {
        return 0;
    }
    return (index < TEMP_AHEAD_CHOICES) ? index : TEMP_AHEAD_CHOICES - 1;
}

//! Applies the chosen degree exactly as a ChoiceMenu choice is applied.
class TemperaturePickerDelegate extends WatchUi.PickerDelegate {

    private var _property as String;

    function initialize(property as String) {
        PickerDelegate.initialize();
        _property = property;
    }

    function onAccept(values as Array) as Boolean {
        var chosen = values[0];
        if (chosen instanceof Number) {
            applySetting(_property, chosen);
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }

    function onCancel() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
