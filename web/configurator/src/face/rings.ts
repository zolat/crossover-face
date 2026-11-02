// Which source each ring actually draws, as StatMap.load() decides it, and the time
// ring's own drawing (TimeRing.mc). The stored values are not always what a ring shows:
// the retired source and a misplaced block read as Off, and a watch with drawn hands
// tells the time in its outermost ring whatever ring1 stores.
import { hueSplit } from "./hueSplit";
import type { Config } from "../codec/configCode";
import { isBlockSource, schema, SOURCE } from "./schema";

export const isTime = (source: number) => schema.timeRing.styles.some((style) => style.value === source);

/** Does this watch give a ring over to the time? */
export const tellsTime = (drawnHands: boolean) => (drawnHands ? schema.timeRing.drawn : schema.timeRing.physical);

/** The four rings' sources, outermost first, as the watch loads them. */
export function effectiveRings(config: Config, drawnHands: boolean): number[] {
  const rings = [config.ring1, config.ring2, config.ring3, config.ring4].map((source, ring) => {
    if (source === SOURCE.SOURCE_RETIRED) return SOURCE.SOURCE_OFF;
    if (isBlockSource(source) && ring > schema.sources.blocksTopRing) return SOURCE.SOURCE_OFF;
    // The time is placed, never chosen: a stored one anywhere else reads as Off.
    if (isTime(source)) return SOURCE.SOURCE_OFF;
    return source;
  });
  if (tellsTime(drawnHands)) {
    const stored = [config.ring1, config.ring2, config.ring3, config.ring4][schema.timeRing.ring];
    rings[schema.timeRing.ring] = isTime(stored) ? stored : schema.timeRing.default;
  }
  return rings;
}

/** The time the preview shows: the forecasts' ten o'clock, at ten past. */
export const SAMPLE_TIME = { hour: 10, minute: 10 };

/** ClockData.timeFractions(): the hour's and the minute's ends, in turns. */
export function timeFractions(hour: number, minute: number): [number, number] {
  const withinHour = minute / 60;
  return [((hour % 12) + withinHour) / 12, withinHour];
}

const NEITHER = 0;
const HOUR = 1;
const MINUTE = 2;

/**
 * TimeRing.slotOf(): which fills cover a dot. Split, the hour takes the innermost
 * sub-band and the minute the rest; overlapping, each takes the whole ring.
 * `edgeSq` is the innermost sub-band's squared outer edge.
 */
export function timeSlot(source: number, radiusSq: number, edgeSq: number, turn: number,
                         hourEnd: number, minuteEnd: number): number {
  const split = source === schema.timeRing.split;
  let slot = NEITHER;
  if ((!split || radiusSq <= edgeSq) && turn < hourEnd) slot += HOUR;
  if ((!split || radiusSq > edgeSq) && turn < minuteEnd) slot += MINUTE;
  return slot;
}

/**
 * TimeRing.coloursFor(): what each slot is painted. Split, white over the ring's unknown
 * tier; overlapping, the ring's own colour where both have passed and its hue split for
 * the hour and minute (Palette.timeOverlap), over a neutral grey.
 */
export function timeColours(source: number, tiers: { band: number; dim: number }): [number, number, number, number] {
  const { colours, splitDegrees, splitSaturation } = schema.timeRing;
  if (source === schema.timeRing.split) return [tiers.dim, colours.lit, colours.lit, colours.lit];
  const [hour, minute] = hueSplit(tiers.band, splitDegrees, splitSaturation);
  return [colours.unlit, hour, minute, tiers.band];
}
