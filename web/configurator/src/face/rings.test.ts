import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { DEFAULT_CONFIG, SOURCE_MAX } from "../codec/configCode";
import type { Lattice } from "./lattice";
import { alwaysOnWorst, BUDGET } from "./luminance";
import { build, themeColours } from "./palette";
import { render } from "./render";
import { effectiveRings, timeColours, timeFractions, timeSlot } from "./rings";
import { schema, SOURCE } from "./schema";

const lattice = (screen: number) =>
  JSON.parse(
    readFileSync(fileURLToPath(new URL(`../../public/geometry/${screen}.json`, import.meta.url)), "utf8"),
  ) as Lattice;

const { split, default: overlap } = schema.timeRing;
const NO_CUSTOM = { colours: [0, 0, 0, 0], ramp: [0, 0, 0] };

/** The innermost sub-band's squared outer edge, as DotGrid.bandEdge[ring * BANDS]. */
function edgeSq(grid: Lattice, ring: number): number {
  const inner = grid.ringEdges[ring];
  const outer = ring === 0 ? grid.radius : grid.ringEdges[ring - 1];
  const edge = inner + Math.trunc((outer - inner) / 3);
  return edge * edge;
}

describe("the time ring", () => {
  it("is offered as two styles, overlap first and by default", () => {
    expect(schema.timeRing.styles.map((style) => style.value)).toEqual([SOURCE.SOURCE_TIME_OVERLAP, SOURCE.SOURCE_TIME]);
    expect(overlap).toBe(SOURCE.SOURCE_TIME_OVERLAP);
    expect(split).toBe(SOURCE.SOURCE_TIME);
    expect(schema.timeRing).toMatchObject({ ring: 0, drawn: true, physical: false });
  });

  it("fits in the code: the codec's top source is the face's", () => {
    expect(SOURCE_MAX).toBe(Math.max(...Object.values(SOURCE)));
  });

  // aHandsFreeWatchAlwaysTellsTheTime, on the page's side.
  it("is placed on a watch with drawn hands and nowhere else", () => {
    const steps = { ...DEFAULT_CONFIG, ring1: SOURCE.SOURCE_STEPS };
    expect(effectiveRings(steps, true)[0]).toBe(overlap);
    expect(effectiveRings({ ...steps, ring1: split }, true)[0]).toBe(split);
    expect(effectiveRings({ ...steps, ring1: split }, false)[0]).toBe(SOURCE.SOURCE_OFF);
    expect(effectiveRings({ ...steps, ring3: overlap }, true)[2]).toBe(SOURCE.SOURCE_OFF);
    expect(effectiveRings(steps, false)[0]).toBe(SOURCE.SOURCE_STEPS);
  });

  it("reads like hands", () => {
    expect(timeFractions(12, 0)).toEqual([0, 0]);
    expect(timeFractions(3, 15)).toEqual([(3 + 0.25) / 12, 0.25]);
    expect(timeFractions(22, 30)).toEqual([10.5 / 12, 0.5]);
  });

  // theTimeRingMatchesTheMockup: the same dots light at 10:27 as in the Monkey C, on
  // the watches that carry a time ring (390 is the 42mm Epix).
  const PINNED: Record<number, [number, number]> = { 390: [280, 129], 416: [323, 150], 454: [301, 143] };
  for (const [screen, [lit, hourLit]] of Object.entries(PINNED)) {
    it(`lights what the face does at 10:27 on ${screen}`, () => {
      const grid = lattice(Number(screen));
      const [hourEnd, minuteEnd] = timeFractions(10, 27);
      let count = 0;
      let hours = 0;
      for (const [dx, dy, ring, , turn] of grid.dots) {
        if (ring !== 0) continue;
        const slot = timeSlot(split, dx * dx + dy * dy, edgeSq(grid, 0), turn, hourEnd, minuteEnd);
        expect(slot).not.toBe(3); // split's two halves tile the ring
        if (slot !== 0) count++;
        if (slot === 1) hours++;
      }
      expect([count, hours]).toEqual([lit, hourLit]);
    });
  }

  it("draws in the preview, held back or not, and only on the outer ring", () => {
    const grid = lattice(416);
    const palette = build(themeColours(0, NO_CUSTOM));
    const config = { ...DEFAULT_CONFIG, alwaysOnFill: 1 };
    const image = { data: new Uint8ClampedArray(416 * 416 * 4), width: 416, height: 416 } as ImageData;
    render(image, grid, palette, config, "alwaysOn", null, true);
    const colours = new Set(timeColours(overlap, palette.rings[0]));
    const at = (dx: number, dy: number) => {
      const i = ((208 + dy) * 416 + 208 + dx) * 4;
      return (image.data[i] << 16) | (image.data[i + 1] << 8) | image.data[i + 2];
    };
    const seen = new Set<number>();
    for (const [dx, dy, ring] of grid.dots) {
      if (ring === 0) {
        expect(colours.has(at(dx, dy))).toBe(true);
        seen.add(at(dx, dy));
      }
    }
    // Ten past ten: unlit, hour only and both, and no minute-only dot past the hour.
    expect(seen).toEqual(new Set(timeColours(overlap, palette.rings[0]).filter((_, slot) => slot !== 2)));
  });

  // theTimeRingFitsTheAlwaysOnBudget: priced at its brightest fill, under the budget.
  for (const screen of [390, 416, 454]) {
    it(`keeps every theme inside the always-on budget at ${screen}`, () => {
      for (const theme of schema.themes) {
        const palette = build(themeColours(theme.id, NO_CUSTOM));
        const without = alwaysOnWorst(lattice(screen), palette).total;
        for (const style of [split, overlap]) {
          const figure = alwaysOnWorst(lattice(screen), palette, style).total;
          expect(figure).toBeGreaterThan(without - 0.01);
          expect(figure).toBeLessThan(BUDGET);
        }
      }
    });
  }
});
