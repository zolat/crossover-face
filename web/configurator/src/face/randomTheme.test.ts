import { describe, expect, it } from "vitest";
import { encode, DEFAULT_CONFIG, THEME_CUSTOM } from "../codec/configCode";
import { hsl, isGood, rampFor, randomTheme } from "./randomTheme";

/** mulberry32: a small seeded generator, so every run tests the same draws. */
function seeded(seed: number) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

describe("random theme", () => {
  it("draws themes nothing would warn about, every time", () => {
    for (let seed = 1; seed <= 500; seed++) {
      const theme = randomTheme(seeded(seed));
      expect(isGood(theme), `seed ${seed}`).toBe(true);
      expect(new Set(theme.ramp).size).toBe(3);
      // And it is a theme the code can carry.
      expect(() => encode({ ...DEFAULT_CONFIG, theme: THEME_CUSTOM, customColours: theme.colours, customRamp: theme.ramp })).not.toThrow();
    }
  });

  it("varies", () => {
    const seen = new Set<string>();
    for (let seed = 1; seed <= 50; seed++) seen.add(randomTheme(seeded(seed)).colours.join());
    expect(seen.size).toBe(50);
  });

  it("runs the ramp from the bluest hue to the reddest", () => {
    const blue = hsl(215, 0.8, 0.6);
    const red = hsl(5, 0.8, 0.6);
    const yellow = hsl(50, 0.8, 0.6);
    const green = hsl(120, 0.8, 0.6);
    expect(rampFor([green, red, blue, yellow])).toEqual([2, 3, 1]);
  });
});
