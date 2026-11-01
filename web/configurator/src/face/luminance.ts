// The always-on budget, measured the way MatrixTest measures it — not the way a
// screenshot or a WCAG contrast checker would. Rec. 709 weights on the *encoded*
// channels (no linearisation), nine lit pixels per cross, over the lattice's own
// pi * RADIUS^2. Pinned to MatrixTest's logged figures by luminance.test.ts.
import type { Lattice } from "./lattice";
import { type BuiltPalette, channel } from "./palette";

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

export function alwaysOnWorst(lattice: Lattice, palette: BuiltPalette): AlwaysOnFigure {
  const area = Math.PI * lattice.radius * lattice.radius;
  const lit = 2 * lattice.dot - 1;
  const solid = lattice.dot * lattice.dot;
  let field = 0;
  lattice.ringCounts.forEach((count, ring) => {
    field += count * lit * relativeLuminance(palette.rings[ring].bandAlwaysOn);
  });
  field /= area;
  const dimmest = Math.min(...palette.rings.map((tiers) => relativeLuminance(tiers.bandAlwaysOn)));
  const brightestMark = Math.max(
    ...palette.rings.flatMap((tiers) => [relativeLuminance(tiers.marker), relativeLuminance(tiers.softMark)]),
  );
  const brightestSun = Math.max(
    ...palette.rings.flatMap((tiers) => [relativeLuminance(tiers.sunrise), relativeLuminance(tiers.sunset)]),
  );
  const rings = palette.rings.length;
  const marks = ((brightestMark * solid - dimmest * lit) * rings) / area;
  const suns = ((brightestSun * solid - dimmest * lit) * rings * 2) / area;
  return { field, marks, suns, total: field + marks + suns };
}
