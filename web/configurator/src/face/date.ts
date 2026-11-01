// The day of the month, as source/matrix/DateGlyph.mc draws it: the numeral's own dots,
// joined by a faint outline running centre to centre through the gaps between crosses.
// tools/mockup.py traces the same edges by the same rule; the test pins both counts.
import type { Lattice } from "./lattice";

const SCALE = 2;
const FONT_COLS = 3;
const FONT_ROWS = 5;
const GUTTER = FONT_COLS;
export const GLYPH_COLS = (2 * FONT_COLS + 1) * SCALE; // 14
export const GLYPH_ROWS = FONT_ROWS * SCALE; // 10

/** 3x5 digits, row-major, bit 14 top-left: DateGlyph.DIGITS. */
const DIGITS = [0x7b6f, 0x2c97, 0x73e7, 0x73cf, 0x5bc9, 0x79cf, 0x79ef, 0x7249, 0x7bef, 0x7bcf];

/** The lines' brightness, by the dateOutline setting: DateGlyph.LINE_PERCENTS. */
export const LINE_PERCENTS = [50, 65, 80];

const digitLit = (digit: number, col: number, row: number) =>
  ((DIGITS[digit] >> (FONT_COLS * FONT_ROWS - 1 - (row * FONT_COLS + col))) & 1) === 1;

/** Is this cell of the 14x10 window part of the day's numeral? */
export function cellLit(day: number, col: number, row: number): boolean {
  const fontCol = Math.floor(col / SCALE);
  if (fontCol === GUTTER) return false;
  const digit = fontCol < GUTTER ? Math.floor(day / 10) : day % 10;
  return digitLit(digit % 10, fontCol % (GUTTER + 1), Math.floor(row / SCALE));
}

/** The window's top-left lattice cell: centred, four rows below the middle. */
export function origin(lattice: Lattice): [number, number] {
  return [(lattice.cols - GLYPH_COLS) / 2, lattice.cols / 2 + 4];
}

/** The window cell a dot offset sits in, or null outside the window. */
export function cellOf(lattice: Lattice, dx: number, dy: number): number | null {
  const [col0, row0] = origin(lattice);
  const half = ((lattice.cols - 1) * lattice.pitch) / 2;
  const col = (dx + half) / lattice.pitch - col0;
  const row = (dy + half) / lattice.pitch - row0;
  if (col < 0 || col >= GLYPH_COLS || row < 0 || row >= GLYPH_ROWS) return null;
  return row * GLYPH_COLS + col;
}

/**
 * The outline, as pairs of window cells one pitch apart. The numeral inset by half a
 * pitch is the union of the squares between every 2x2 block of numeral cells; a unit
 * edge between neighbouring centres is on the outline when that shape lies on exactly
 * one side of it. DateGlyph.trace() and mockup.contour_segments() are the same rule.
 */
export function outline(day: number): [number, number][] {
  const numeral = (c: number, r: number) =>
    c >= 0 && r >= 0 && c < GLYPH_COLS && r < GLYPH_ROWS && cellLit(day, c, r);
  const inside = (c: number, r: number) =>
    numeral(c, r) && numeral(c + 1, r) && numeral(c, r + 1) && numeral(c + 1, r + 1);
  const out: [number, number][] = [];
  for (let r = 0; r < GLYPH_ROWS; r++) {
    for (let c = 0; c < GLYPH_COLS; c++) {
      const here = r * GLYPH_COLS + c;
      if (c + 1 < GLYPH_COLS && inside(c, r - 1) !== inside(c, r)) out.push([here, here + 1]);
      if (r + 1 < GLYPH_ROWS && inside(c - 1, r) !== inside(c, r)) out.push([here, here + GLYPH_COLS]);
    }
  }
  return out;
}

/** A colour at `percent`, channel by channel, truncating as DateGlyph.dimmed() does. */
export function dimmed(colour: number, percent: number): number {
  const r = Math.trunc((((colour >> 16) & 0xff) * percent) / 100);
  const g = Math.trunc((((colour >> 8) & 0xff) * percent) / 100);
  const b = Math.trunc(((colour & 0xff) * percent) / 100);
  return (r << 16) | (g << 8) | b;
}

/** A line fills the gap between two crosses and never their arms. */
export function gap(lattice: Lattice): { from: number; length: number } {
  const from = Math.floor(lattice.dot / 2) + 1;
  return { from, length: lattice.pitch - 2 * from + 1 };
}
