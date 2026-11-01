import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { DEFAULT_CONFIG } from "../codec/configCode";
import { cellLit, cellOf, GLYPH_COLS, GLYPH_ROWS, outline } from "./date";
import type { Lattice } from "./lattice";
import { build, themeColours } from "./palette";
import { render } from "./render";

const lattice = (screen: number) =>
  JSON.parse(
    readFileSync(fileURLToPath(new URL(`../../public/geometry/${screen}.json`, import.meta.url)), "utf8"),
  ) as Lattice;

const numeralCells = (day: number) => {
  const out: number[] = [];
  for (let r = 0; r < GLYPH_ROWS; r++) for (let c = 0; c < GLYPH_COLS; c++) if (cellLit(day, c, r)) out.push(r * GLYPH_COLS + c);
  return out;
};

describe("the date", () => {
  // tools/mockup.py: (len(glyph_cells(d)), len(contour_segments(d))) for these days.
  const MOCKUP: Record<number, [number, number]> = { 1: [80, 80], 8: [100, 100], 15: [76, 76], 28: [96, 96], 31: [76, 76] };
  for (const [day, [cells, segments]] of Object.entries(MOCKUP)) {
    it(`matches the mockup's numeral and outline for day ${day}`, () => {
      expect(numeralCells(Number(day))).toHaveLength(cells);
      expect(outline(Number(day))).toHaveLength(segments);
    });
  }

  it("closes its outline through every numeral dot exactly once, every day", () => {
    for (let day = 1; day <= 31; day++) {
      const degree = new Map<number, number>();
      for (const [a, b] of outline(day)) for (const cell of [a, b]) degree.set(cell, (degree.get(cell) ?? 0) + 1);
      const cells = numeralCells(day);
      expect([...degree.keys()].sort((x, y) => x - y)).toEqual(cells);
      expect([...degree.values()].every((n) => n === 2)).toBe(true);
    }
  });

  for (const screen of [390, 416, 454]) {
    it(`finds a dot under every window cell at ${screen}`, () => {
      const grid = lattice(screen);
      const found = new Set(grid.dots.map(([dx, dy]) => cellOf(grid, dx, dy)).filter((cell) => cell !== null));
      expect(found.size).toBe(GLYPH_COLS * GLYPH_ROWS);
    });
  }

  it("draws awake and not always-on, and only when it is on", () => {
    const grid = lattice(390);
    const palette = build(themeColours(0, { colours: [0, 0, 0, 0], ramp: [0, 0, 0] }));
    const lit = (showDate: number, mode: "awake" | "alwaysOn") => {
      const image = { data: new Uint8ClampedArray(390 * 390 * 4), width: 390, height: 390 } as ImageData;
      render(image, grid, palette, { ...DEFAULT_CONFIG, showDate }, mode, 15);
      let count = 0;
      for (let i = 0; i < image.data.length; i += 4) if (image.data[i] | image.data[i + 1] | image.data[i + 2]) count++;
      return count;
    };
    // Day 15 is 76 segments, each filling a five-pixel gap no cross touches.
    expect(lit(1, "awake") - lit(0, "awake")).toBe(76 * 5);
    expect(lit(1, "alwaysOn")).toBe(lit(0, "alwaysOn"));
  });
});
