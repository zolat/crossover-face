// Illustrative readings for the preview. The page cannot know the wearer's steps or
// tomorrow's rain, so each source shows one fixed, typical reading — enough to see how a
// colour reads filled, unfilled and, for a forecast, unknown.
import { SOURCE } from "./schema";

export interface Reading {
  /** [start, end] in turns; end < start wraps past twelve, as on the watch. */
  span?: [number, number];
  /** A solid dot at this position: the current temperature. */
  mark?: number;
  /** Sunrise on the ring's inner edge, sunset on its outer edge, in turns. */
  sun?: [number, number];
  /** Twelve hour slots, clock position 0..11, each a level 0..15 or null for unknown. */
  blocks?: (number | null)[];
}

const hour = (h: number, m = 0) => ((h % 12) + m / 60) / 12;

const BY_SOURCE: Record<number, { awake: Reading; alwaysOn: Reading }> = {};

function both(source: number, reading: Reading, asleep: Reading = reading) {
  BY_SOURCE[source] = { awake: reading, alwaysOn: asleep };
}

// Temperature range on the 0-60 °C dial: 18 to 31 today, 24.6 now.
const tempSpan: [number, number] = [18 / 60, 31 / 60];
both(SOURCE.SOURCE_STEPS, { span: [0, 0.62] });
both(SOURCE.SOURCE_BATTERY, { span: [0, 0.81] });
both(SOURCE.SOURCE_BODY_BATTERY, { span: [0, 0.58] });
both(SOURCE.SOURCE_INTENSITY_MINUTES, { span: [0, 0.34] });
both(SOURCE.SOURCE_RAIN, { span: [0, 0.3] });
// Seconds reports nothing in always-on.
both(SOURCE.SOURCE_SECONDS, { span: [0, 0.42] }, {});
both(SOURCE.SOURCE_TEMPERATURE, { span: tempSpan, mark: 24.6 / 60 });
both(SOURCE.SOURCE_TEMP_SUN, { span: tempSpan, mark: 24.6 / 60, sun: [hour(6, 5), hour(18, 10)] });
// Forecasts start at the current hour, ten o'clock, and run clockwise; the last two
// hours are past the forecast's reach, which the face draws as unknown.
both(SOURCE.SOURCE_RAIN_HOURS, { blocks: [0, 0, null, null, 0, 2, 5, 9, 12, 15, 10, 4] });
both(SOURCE.SOURCE_UV_HOURS, { blocks: [7, 4, null, null, 0, 0, 0, 0, 0, 3, 6, 9] });
both(SOURCE.SOURCE_TEMP_HOURS, { blocks: [12, 11, null, null, 4, 4, 5, 5, 6, 8, 10, 12] });
// Body Battery history: the current hour is live and the rest read back anticlockwise.
both(SOURCE.SOURCE_BODY_BATTERY_HOURS, { blocks: [12, 13, 14, 15, 15, 15, 14, 12, 11, 10, 9, 8] });

export function readingFor(source: number, alwaysOn: boolean): Reading {
  const found = BY_SOURCE[source];
  if (!found) return {};
  return alwaysOn ? found.alwaysOn : found.awake;
}

export function inSpan(turn: number, span: [number, number]): boolean {
  const [start, end] = span;
  return start <= end ? turn >= start && turn < end : turn >= start || turn < end;
}
