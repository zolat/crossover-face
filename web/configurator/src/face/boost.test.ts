import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import type { Lattice } from "./lattice";
import { alwaysOnWorst, BUDGET } from "./luminance";
import { lighten, toOklch } from "./oklch";
import { boostedTheme, build, themeColours } from "./palette";
import { schema } from "./schema";

const lattice = (name: string) =>
  JSON.parse(readFileSync(fileURLToPath(new URL(`../../public/geometry/${name}.json`, import.meta.url)), "utf8")) as Lattice;
const NO_CUSTOM = { colours: [0, 0, 0, 0, 0], ramp: [0, 0, 0] };

// tools/mockup.py's lighten() at Bright and Brightest, every shipping colour in theme
// order — the same table BoostTest.LIGHTEN_PINS holds the watch to.
const PINS: Record<string, [number[], number[]]> = {
  Terrain: [[0xf4aaff, 0xcbea61, 0xb0e3ff, 0xffa699, 0xfdcb56], [0xfad2ff, 0xdcfb73, 0xd6f0ff, 0xffd1ca, 0xffe4ab]],
  Activity: [[0xff968d, 0x8ae36d, 0x7db9ff, 0xffb951, 0xb2acff], [0xffc9c3, 0xa2fd86, 0xbbdaff, 0xffdbac, 0xd4d3ff]],
  Beacon: [[0x86ebff, 0xff968d, 0xb2acff, 0xffb951, 0xcbea61], [0xc3f5ff, 0xffc9c3, 0xd4d3ff, 0xffdbac, 0xdcfb73]],
  Pulse: [[0xff968d, 0x52f0dc, 0xf4aaff, 0xcbea61, 0xb0e3ff], [0xffc9c3, 0x92ffee, 0xfad2ff, 0xdcfb73, 0xd6f0ff]],
  "Lemon & Azure": [[0xfde95f, 0x8ac0ff, 0xfde95f, 0x8ac0ff, 0xfde95f], [0xfff5ab, 0xc1ddff, 0xfff5ab, 0xc1ddff, 0xfff5ab]],
  "Emerald & Violet": [[0x5df79f, 0xcaadff, 0x5df79f, 0xcaadff, 0x5df79f], [0xabffc8, 0xe1d3ff, 0xabffc8, 0xe1d3ff, 0xabffc8]],
  "Orchid & Lime": [[0xf4aaff, 0xcbea61, 0xf4aaff, 0xcbea61, 0xf4aaff], [0xfad2ff, 0xdcfb73, 0xfad2ff, 0xdcfb73, 0xfad2ff]],
};

const near = (a: number, b: number) => [16, 8, 0].every((shift) => Math.abs(((a >> shift) & 255) - ((b >> shift) & 255)) <= 1);
const arc = (a: number, b: number) => Math.min(Math.abs(a - b), 360 - Math.abs(a - b));

describe("the always-on boost", () => {
  it("is off by default and then leaves the theme alone", () => {
    const theme = themeColours(0, NO_CUSTOM);
    expect(schema.palette.BOOST_AMOUNTS[0]).toBe(0);
    expect(boostedTheme(theme, 0)).toBe(theme);
  });

  it("lightens every shipping colour as the mockup does", () => {
    for (const theme of schema.themes) {
      for (const level of [1, 2]) {
        theme.colours.forEach((colour, i) => {
          const got = lighten(colour, schema.palette.BOOST_AMOUNTS[level]);
          expect(near(got, PINS[theme.name][level - 1][i]), `${theme.name} ${level} #${got.toString(16)}`).toBe(true);
        });
      }
    }
  });

  it("raises lightness and keeps the hue", () => {
    for (const theme of schema.themes) {
      for (const colour of theme.colours) {
        const [L, , h] = toOklch(colour);
        let previous = L;
        for (const level of [1, 2]) {
          const [lifted, , hue] = toOklch(lighten(colour, schema.palette.BOOST_AMOUNTS[level]));
          expect(lifted).toBeGreaterThan(previous);
          expect(arc(hue, h)).toBeLessThan(2);
          previous = lifted;
        }
      }
    }
  });

  it("gives a dark colour more than a light one", () => {
    const gain = (colour: number) => toOklch(lighten(colour, schema.palette.BOOST_AMOUNTS[1]))[0] - toOklch(colour)[0];
    expect(gain(0x203060)).toBeGreaterThan(gain(0x7fd4ff));
  });

  // everyThemeFitsTheAlwaysOnBudget, at every level: the brightest frame, with marks
  // and sun dots, stays under 10% — which all-white already proves for any colours.
  for (const name of ["390-hands", "390", "416", "454"]) {
    it(`keeps every theme inside the always-on budget at every level on ${name}`, () => {
      for (const theme of schema.themes) {
        let previous = 0;
        for (const level of [0, 1, 2]) {
          const figure = alwaysOnWorst(lattice(name), build(boostedTheme(theme, level))).total;
          expect(figure).toBeLessThan(BUDGET);
          expect(figure).toBeGreaterThan(previous);
          previous = figure;
        }
      }
    });
  }
});
