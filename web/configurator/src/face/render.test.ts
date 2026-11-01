import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import type { Lattice } from "./lattice";
import { blockTier } from "./render";
import { schema } from "./schema";

const lattice = (screen: number) =>
  JSON.parse(
    readFileSync(fileURLToPath(new URL(`../../public/geometry/${screen}.json`, import.meta.url)), "utf8"),
  ) as Lattice;

describe("block rings", () => {
  it("are offered on ring 3 and not on the innermost", () => {
    const ring3 = schema.settings.find((setting) => setting.key === "ring3")!.options!.map((option) => option.value);
    const ring4 = schema.settings.find((setting) => setting.key === "ring4")!.options!.map((option) => option.value);
    for (const source of schema.sources.blocks) {
      expect(ring3).toContain(source);
      expect(ring4).not.toContain(source);
    }
  });

  // everyNonZeroLevelLightsAtLeastOneDot, on the preview's side: with ring 3's window
  // floor every rung of every hour lights something, on every offered ring and screen.
  for (const screen of [390, 416, 454]) {
    it(`light a dot at every level in every hour at ${screen}`, () => {
      const grid = lattice(screen);
      for (let ring = 0; ring <= schema.sources.blocksTopRing; ring++) {
        for (let level = 1; level <= 15; level++) {
          const blocks = Array(12).fill(level);
          const lit = new Set<number>();
          for (const [dx, dy, dotRing, , turn] of grid.dots) {
            if (dotRing === ring && blockTier(grid, ring, dx, dy, turn, blocks) === "band") lit.add(Math.floor(turn * 12) % 12);
          }
          expect(lit.size, `ring ${ring} level ${level}`).toBe(12);
        }
      }
    });
  }
});
