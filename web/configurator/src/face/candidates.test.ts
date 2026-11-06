import { describe, expect, it } from "vitest";
import { DEFAULT_CONFIG, encode, THEME_CUSTOM, tryDecode } from "../codec/configCode";
import { CANDIDATES, candidateFor, duoTone } from "./candidates";
import { isDull } from "./dull";
import { build } from "./palette";
import { isGood } from "./randomTheme";
import { distance } from "./warnings";

/** Further apart than any random theme's neighbours must be (randomTheme's SPREAD, 28). */
const PAIR_DISTANCE = 60;

describe("duo-tone candidates", () => {
  it("are ten, each named once", () => {
    expect(CANDIDATES).toHaveLength(10);
    expect(new Set(CANDIDATES.map((c) => c.name)).size).toBe(10);
    expect(new Set(CANDIDATES.map((c) => c.pair.join())).size).toBe(10);
  });

  it.each(CANDIDATES.map((c) => [c.name, c] as const))("%s alternates its two colours", (_, candidate) => {
    const [a, b] = candidate.pair;
    expect(duoTone(candidate).colours).toEqual([a, b, a, b, a]);
  });

  it.each(CANDIDATES.map((c) => [c.name, c] as const))("%s is bright, lively and nothing warns about it", (_, candidate) => {
    const theme = duoTone(candidate);
    for (const colour of candidate.pair) expect(isDull(colour), colour.toString(16)).toBe(false);
    expect(isGood(theme)).toBe(true);
    expect(distance(...candidate.pair)).toBeGreaterThan(PAIR_DISTANCE);
  });

  it.each(CANDIDATES.map((c) => [c.name, c] as const))("%s runs its ramp from one colour to the other", (_, candidate) => {
    const { ramp } = build(duoTone(candidate));
    expect(new Set([ramp[0], ramp.at(-1)]).size).toBe(2);
    expect(candidate.pair).toContain(ramp[0]);
    expect(candidate.pair).toContain(ramp.at(-1));
  });

  it("carries through a config code and is recognised coming back", () => {
    for (const candidate of CANDIDATES) {
      const theme = duoTone(candidate);
      const decoded = tryDecode(encode({ ...DEFAULT_CONFIG, theme: THEME_CUSTOM, customColours: theme.colours, customRamp: theme.ramp }));
      expect(decoded.ok).toBe(true);
      if (!decoded.ok) continue;
      expect(candidateFor(decoded.config.customColours, decoded.config.customRamp)).toBe(candidate);
    }
  });

  it("recognises nothing that is not a candidate", () => {
    expect(candidateFor(DEFAULT_CONFIG.customColours, DEFAULT_CONFIG.customRamp)).toBeNull();
  });
});
