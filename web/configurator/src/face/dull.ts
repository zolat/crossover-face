// Which colours are too dull to read on the watch, and the nearest one that is not.
//
// Dull is two floors in OKLCH: too dark (lightness) or too grey (chroma). A ring's
// unfilled tier is about half its colour, and the AMOLED crushes dark levels a monitor
// shows, so a colour that looks fine on the page can vanish on the wrist. The floors sit
// just under the dullest shipping colours (Activity's blue for lightness, Terrain's ice
// for chroma) until tools/dull_ladder.py settles them on a watch.
//
// The wheel picks in HSV (hue round it, saturation out from the centre, value on a
// slider), so snapping happens there too: along the axis the wearer was moving first,
// so the marker does not jump sideways.
import { toOklch } from "./oklch";

export interface Floor {
  lightness: number;
  chroma: number;
}

export const DULL: Floor = { lightness: 0.6, chroma: 0.09 };

export function isDull(colour: number, floor: Floor = DULL): boolean {
  const [L, C] = toOklch(colour);
  return L < floor.lightness || C < floor.chroma;
}

/** Hue in degrees, saturation and value 0..1. */
export type Hsv = [number, number, number];

export function toHsv(colour: number): Hsv {
  const r = ((colour >> 16) & 255) / 255;
  const g = ((colour >> 8) & 255) / 255;
  const b = (colour & 255) / 255;
  const max = Math.max(r, g, b);
  const d = max - Math.min(r, g, b);
  let h = 0;
  if (d > 0) h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return [(h * 60 + 360) % 360, max === 0 ? 0 : d / max, max];
}

export function fromHsv([hue, s, v]: Hsv): number {
  const h = (((hue % 360) + 360) % 360) / 60;
  const c = v * s;
  const x = c * (1 - Math.abs((h % 2) - 1));
  const [r, g, b] = h < 1 ? [c, x, 0] : h < 2 ? [x, c, 0] : h < 3 ? [0, c, x] : h < 4 ? [0, x, c] : h < 5 ? [x, 0, c] : [c, 0, x];
  const m = v - c;
  const to = (u: number) => Math.round((u + m) * 255);
  return (to(r) << 16) | (to(g) << 8) | to(b);
}

const STEPS = 100;

/**
 * The nearest colour at this hue that is not dull: along `axis` first (saturation for a
 * point on the wheel, value for the brightness slider), and anywhere at this hue only if
 * nothing on that line will do. Returns the point unchanged when it is already lively.
 */
export function lively(point: Hsv, axis: "s" | "v", floor: Floor = DULL): Hsv {
  const [h, s, v] = point;
  if (!isDull(fromHsv(point), floor)) return point;
  const along = axis === "s" ? 1 : 2;
  let best: Hsv | null = null;
  let bestGap = Infinity;
  for (let i = 0; i <= STEPS; i++) {
    const candidate: Hsv = [h, s, v];
    candidate[along] = i / STEPS;
    const gap = Math.abs(candidate[along] - point[along]);
    if (gap < bestGap && !isDull(fromHsv(candidate), floor)) {
      best = candidate;
      bestGap = gap;
    }
  }
  if (best) return best;
  for (let i = 0; i <= STEPS; i++) {
    for (let j = 0; j <= STEPS; j++) {
      const candidate: Hsv = [h, i / STEPS, j / STEPS];
      const gap = Math.hypot(candidate[1] - s, candidate[2] - v);
      if (gap < bestGap && !isDull(fromHsv(candidate), floor)) {
        best = candidate;
        bestGap = gap;
      }
    }
  }
  return best ?? point;
}
