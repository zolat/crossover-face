// The always-on budget, measured the way MatrixTest measures it — not the way a
// screenshot or a WCAG contrast checker would. Rec. 709 weights on the *encoded*
// channels (no linearisation), nine lit pixels per cross, over the lattice's own
// pi * RADIUS^2. Pinned to MatrixTest's logged figures by luminance.test.ts.
import type { Lattice } from "./lattice";
import { type BuiltPalette, channel } from "./palette";
import { timeColours } from "./rings";
import { schema } from "./schema";

export const BUDGET = 0.1;

export function relativeLuminance(colour: number): number {
  return (0.2126 * channel(colour, 16) + 0.7152 * channel(colour, 8) + 0.0722 * channel(colour, 0)) / 255;
}

export interface AlwaysOnFigure {
  /** Every dot lit in its always-on band: the brightest field the face draws. */
  field: number;
  /** The brightest mark, solid, replacing the dimmest band's cross, on every ring. */
  marks: number;
  /** Both sun dots on every ring, priced the same way. */
  suns: number;
  total: number;
}

/**
 * `timeStyle` is the time ring's source on a watch that carries one. That ring is priced
 * at its brightest fill — the time is drawn in every power mode, and just before twelve
 * it fills the whole ring — instead of at its theme band.
 */
export function alwaysOnWorst(lattice: Lattice, palette: BuiltPalette, timeStyle?: number): AlwaysOnFigure {
  const area = Math.PI * lattice.radius * lattice.radius;
  const lit = 2 * lattice.dot - 1;
  const solid = lattice.dot * lattice.dot;
  let field = 0;
  lattice.ringCounts.forEach((count, ring) => {
    const timed = timeStyle !== undefined && ring === schema.timeRing.ring;
    const brightest = timed
      ? Math.max(...timeColours(timeStyle, palette.rings[ring]).slice(1).map(relativeLuminance))
      : relativeLuminance(palette.rings[ring].bandAlwaysOn);
    field += count * lit * brightest;
  });
  field /= area;
  // Priced over the rings this lattice has: a theme carries five colours, and a
  // four-ring watch never draws the fifth. As the watch's tests loop StatMap.RINGS.
  const rings = lattice.ringCounts.length;
  const drawn = palette.rings.slice(0, rings);
  const dimmest = Math.min(...drawn.map((tiers) => relativeLuminance(tiers.bandAlwaysOn)));
  const brightestMark = Math.max(
    ...drawn.flatMap((tiers) => [relativeLuminance(tiers.marker), relativeLuminance(tiers.softMark)]),
  );
  const brightestSun = Math.max(
    ...drawn.flatMap((tiers) => [relativeLuminance(tiers.sunrise), relativeLuminance(tiers.sunset)]),
  );
  const marks = ((brightestMark * solid - dimmest * lit) * rings) / area;
  const suns = ((brightestSun * solid - dimmest * lit) * rings * 2) / area;
  return { field, marks, suns, total: field + marks + suns };
}
