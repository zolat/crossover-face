// What a custom theme can get wrong that the budget does not catch. No colour choice can
// cross the 10% always-on limit (ConfigCodeTest proves all-white fits), so these are about
// legibility, the things everyThemeKeepsTheTierOrder guards for the shipping themes.
import { relativeLuminance } from "./luminance";
import type { BuiltPalette } from "./palette";
import { channel } from "./palette";

function lab(colour: number): [number, number, number] {
  const lin = (c: number) => {
    const v = c / 255;
    return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  };
  const [r, g, b] = [lin(channel(colour, 16)), lin(channel(colour, 8)), lin(channel(colour, 0))];
  const x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  const y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  const z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  const f = (t: number) => (t > 216 / 24389 ? Math.cbrt(t) : (24389 / 27 * t + 16) / 116);
  return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
}

export function distance(a: number, b: number): number {
  const [l1, a1, b1] = lab(a);
  const [l2, a2, b2] = lab(b);
  return Math.hypot(l1 - l2, a1 - a2, b1 - b2);
}

/** Below this the two rings blur together at a glance. Activity's closest pair is ~40. */
export const NEIGHBOUR_DISTANCE = 15;
/** An always-on band dimmer than this barely shows on the AMOLED. */
export const DARKEST_BAND = 0.06;

export function themeWarnings(palette: BuiltPalette): string[] {
  const out: string[] = [];
  const name = (ring: number) => (ring === 0 ? "the outer ring" : ring === 3 ? "the inner ring" : `ring ${ring + 1}`);
  palette.rings.forEach((tiers, ring) => {
    if (relativeLuminance(tiers.bandAlwaysOn) < DARKEST_BAND) {
      out.push(`The colour for ${name(ring)} is very dark, so it will barely show.`);
    } else if (relativeLuminance(tiers.over) <= relativeLuminance(tiers.band)) {
      out.push(`The colour for ${name(ring)} is so close to white that a second lap past the goal will not stand out.`);
    }
  });
  for (let ring = 0; ring + 1 < palette.rings.length; ring++) {
    if (distance(palette.rings[ring].band, palette.rings[ring + 1].band) < NEIGHBOUR_DISTANCE) {
      out.push(`The colours for ${name(ring)} and ${name(ring + 1)} are hard to tell apart side by side.`);
    }
  }
  return out;
}
