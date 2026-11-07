import { describe, expect, it } from "vitest";
import { DEFAULT_CONFIG, encode, THEME_CUSTOM, tryDecode } from "../codec/configCode";
import { duoTone, EXTENDED, extendedFor } from "./extended";
import { isDull } from "./dull";
import { build } from "./palette";
import { isGood } from "./randomTheme";
import { schema } from "./schema";
import { distance } from "./warnings";

/** Further apart than any random theme's neighbours must be (randomTheme's SPREAD, 28). */
const PAIR_DISTANCE = 60;

/** The duo-tones the watch ships, by persisted ID: Palette.THEMES and RAMP_STOPS. */
const SHIPPED: [number, string, [number, number]][] = [
  [9, "Lemon & Azure", [0xf0dc50, 0x3d9bff]],
  [10, "Emerald & Violet", [0x3fe08a, 0xb07cff]],
  [11, "Orchid & Lime", [0xe879f9, 0xb8d64b]],
];
const ALL = [...EXTENDED, ...SHIPPED.map(([, name, pair]) => ({ name, pair }))];

describe("duo-tone themes", () => {
  it("the extended library is the seven that did not ship, each once", () => {
    expect(EXTENDED).toHaveLength(7);
    expect(new Set(ALL.map((entry) => entry.name)).size).toBe(10);
    expect(new Set(ALL.map((entry) => entry.pair.join())).size).toBe(10);
    for (const entry of EXTENDED) expect(schema.themes.map((theme) => theme.name)).not.toContain(entry.name);
  });

  it.each(SHIPPED)("shipping theme %i, %s, is built by the same rule", (id, name, pair) => {
    const theme = schema.themes.find((entry) => entry.id === id);
    expect(theme?.name).toBe(name);
    const expected = duoTone({ name, pair });
    expect(theme?.colours).toEqual(expected.colours);
    expect(theme?.ramp).toEqual(expected.ramp);
  });

  it.each(ALL.map((entry) => [entry.name, entry] as const))("%s alternates its two colours", (_, entry) => {
    const [a, b] = entry.pair;
    expect(duoTone(entry).colours).toEqual([a, b, a, b, a]);
  });

  it.each(ALL.map((entry) => [entry.name, entry] as const))("%s is bright, lively and nothing warns about it", (_, entry) => {
    const theme = duoTone(entry);
    for (const colour of entry.pair) expect(isDull(colour), colour.toString(16)).toBe(false);
    expect(isGood(theme)).toBe(true);
    expect(distance(...entry.pair)).toBeGreaterThan(PAIR_DISTANCE);
  });

  it.each(ALL.map((entry) => [entry.name, entry] as const))("%s runs its ramp from one colour to the other", (_, entry) => {
    const { ramp } = build(duoTone(entry));
    expect(new Set([ramp[0], ramp.at(-1)]).size).toBe(2);
    expect(entry.pair).toContain(ramp[0]);
    expect(entry.pair).toContain(ramp.at(-1));
  });

  it("an extended theme carries through a config code and is recognised coming back", () => {
    for (const entry of EXTENDED) {
      const theme = duoTone(entry);
      const decoded = tryDecode(encode({ ...DEFAULT_CONFIG, theme: THEME_CUSTOM, customColours: theme.colours, customRamp: theme.ramp }));
      expect(decoded.ok).toBe(true);
      if (!decoded.ok) continue;
      expect(extendedFor(decoded.config.customColours, decoded.config.customRamp)).toBe(entry);
    }
  });

  it("recognises nothing that is not in the library", () => {
    expect(extendedFor(DEFAULT_CONFIG.customColours, DEFAULT_CONFIG.customRamp)).toBeNull();
  });
});
