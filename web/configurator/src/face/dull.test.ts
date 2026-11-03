import { describe, expect, it } from "vitest";
import { DULL, fromHsv, isDull, lively, toHsv } from "./dull";
import { toOklch } from "./oklch";
import { randomTheme } from "./randomTheme";
import { schema } from "./schema";

/** A seeded generator, so a failing draw can be replayed. */
function seeded(seed: number) {
  let state = seed;
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 2 ** 32;
  };
}

describe("dull colours", () => {
  it("leave every shipping colour pickable", () => {
    for (const theme of schema.themes) {
      for (const colour of theme.colours) expect(isDull(colour), `${theme.name} #${colour.toString(16)}`).toBe(false);
    }
  });

  it("are the greys, the near-whites and the darks", () => {
    for (const colour of [0x000000, 0x808080, 0xffffff, 0xf0e8f0, 0x400000, 0x0000ff, 0x2a4a2a]) {
      expect(isDull(colour), `#${colour.toString(16)}`).toBe(true);
    }
  });

  it("are measured by the two floors and nothing else", () => {
    for (const colour of [0x7fd4ff, 0x1f8ffe, 0xff00ff, 0x9a9a9a, 0x3a3a3a]) {
      const [L, C] = toOklch(colour);
      expect(isDull(colour)).toBe(L < DULL.lightness || C < DULL.chroma);
    }
    expect(isDull(0x7fd4ff, { lightness: 0.6, chroma: 0.11 })).toBe(true);
  });

  it("are never what Randomise draws", () => {
    const random = seeded(7);
    for (let i = 0; i < 300; i++) {
      for (const colour of randomTheme(random).colours) expect(isDull(colour), `#${colour.toString(16)}`).toBe(false);
    }
  });
});

describe("HSV", () => {
  it("round-trips a colour", () => {
    for (const colour of [0xfe4646, 0x6dc54f, 0x1f8ffe, 0xe59a0a, 0x8e7bff, 0x000000, 0xffffff, 0x123456]) {
      expect(fromHsv(toHsv(colour))).toBe(colour);
    }
  });

  it("puts red at hue 0 and blue at 240", () => {
    expect(toHsv(0xff0000)[0]).toBe(0);
    expect(toHsv(0x0000ff)[0]).toBe(240);
  });
});

describe("the nearest lively colour", () => {
  it("leaves a lively one alone", () => {
    const point = toHsv(0xfe4646);
    expect(lively(point, "s")).toEqual(point);
  });

  it("pushes a grey out from the centre of the wheel, keeping hue and brightness", () => {
    const [h, s, v] = lively([30, 0, 1], "s");
    expect([h, v]).toEqual([30, 1]);
    expect(s).toBeGreaterThan(0);
    expect(isDull(fromHsv([h, s, v]))).toBe(false);
    // and no further than it has to
    expect(isDull(fromHsv([h, s - 0.01, v]))).toBe(true);
  });

  it("raises a dark colour's brightness, keeping hue and saturation", () => {
    const [h, s, v] = lively([120, 0.7, 0.3], "v");
    expect([h, s]).toEqual([120, 0.7]);
    expect(isDull(fromHsv([h, s, v]))).toBe(false);
    expect(isDull(fromHsv([h, s, v - 0.01]))).toBe(true);
  });

  it("moves off its axis only when nothing on it will do", () => {
    // Too dark for any saturation at this brightness.
    const out = lively([200, 0.5, 0.2], "s");
    expect(isDull(fromHsv(out))).toBe(false);
    expect(out[0]).toBe(200);
    expect(out[2]).toBeGreaterThan(0.2);
  });

  it("finds a lively colour at every hue", () => {
    for (let hue = 0; hue < 360; hue += 5) expect(isDull(fromHsv(lively([hue, 0, 0], "s")))).toBe(false);
  });
});
