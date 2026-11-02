import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import type { Lattice } from "./lattice";
import { alwaysOnWorst } from "./luminance";
import { build, mix, scale, themeColours } from "./palette";
import { schema } from "./schema";

const lattice = (key: string) =>
  JSON.parse(
    readFileSync(fileURLToPath(new URL(`../../public/geometry/${key}.json`, import.meta.url)), "utf8"),
  ) as Lattice;

// What MatrixTest logs for each shipping theme — everyThemeFitsTheAlwaysOnBudget,
// theAlwaysOnMarkFitsTheBudget and theSunDotsFitTheAlwaysOnBudget — captured from the
// suite: the Crossover's 390-hands on 2026-11-01, the 454 Epix on 2026-11-02 with five
// rings measured from the centre. The acceptance bar is 0.1 points; these agree to the log's six digits, so a
// drift in the formula shows long before it matters.
const LOGGED: Record<string, Record<number, [number, number, number]>> = {
  "390-hands": { 0: [0.060301, 0.0006, 0.001083], 1: [0.047197, 0.000583, 0.001017],
                 7: [0.05269, 0.000626, 0.001125], 8: [0.0514, 0.000635, 0.001153] },
  "454": { 0: [0.061738, 0.000614, 0.001108], 1: [0.048456, 0.000597, 0.001041],
           7: [0.054977, 0.00065, 0.00118], 8: [0.053707, 0.00065, 0.00118] },
};
const NO_CUSTOM = { colours: [0, 0, 0, 0], ramp: [0, 0, 0] };

describe("always-on luminance", () => {
  for (const [key, themes] of Object.entries(LOGGED)) {
    for (const [theme, [field, marks, suns]] of Object.entries(themes)) {
      it(`matches MatrixTest for theme ${theme} at ${key}`, () => {
        const figure = alwaysOnWorst(lattice(key), build(themeColours(Number(theme), NO_CUSTOM)));
        expect(figure.field).toBeCloseTo(field, 5);
        expect(figure.marks).toBeCloseTo(marks, 5);
        expect(figure.suns).toBeCloseTo(suns, 5);
      });
    }
  }

  it("matches ConfigCodeTest's all-white custom theme, under budget", () => {
    const white = build({ colours: [0xffffff, 0xffffff, 0xffffff, 0xffffff], ramp: [0, 1, 2] });
    const figure = alwaysOnWorst(lattice("390-hands"), white);
    expect(figure.field).toBeCloseTo(0.088245, 5);
    expect(figure.marks).toBeCloseTo(0.000564, 5);
    expect(figure.suns).toBeCloseTo(0.00107, 5);
    for (const key of ["390-hands", "390", "416", "454"]) {
      expect(alwaysOnWorst(lattice(key), white).total).toBeLessThan(0.1);
    }
  });
});

describe("palette", () => {
  it("draws Terrain's exact colours and ramp ends", () => {
    const terrain = build(themeColours(0, NO_CUSTOM));
    expect(terrain.rings.map((tiers) => tiers.band)).toEqual([0xe879f9, 0xb8d64b, 0x7fd4ff, 0xff6b5b, 0xe5b33a]);
    expect(terrain.ramp[0]).toBe(0x7fd4ff);
    expect(terrain.ramp[schema.palette.RAMP_STEPS - 1]).toBe(0xff6b5b);
  });

  it("truncates like Monkey C rather than rounding", () => {
    // 0xE5 * 0.55 = 125.95 -> 125 (0x7D), as Palette.dimOf comment's gold #7D5405 shows.
    expect(scale(0xe59a0a, 0.55)).toBe(0x7d5405);
    expect(mix(0xffffff, 0x000000, 0.5)).toBe(0x7f7f7f);
  });

  it("takes a custom theme's colours and stops as given", () => {
    const custom = build({ colours: [0x123456, 0xabcdef, 0x00ff00, 0xff8000], ramp: [3, 1, 0] });
    expect(custom.rings[1].band).toBe(0xabcdef);
    expect(custom.ramp[0]).toBe(0xff8000);
    expect(custom.ramp[custom.ramp.length - 1]).toBe(0x123456);
  });
});
