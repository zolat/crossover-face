import { describe, expect, it } from "vitest";
import { schema } from "./schema";
import { hueSplit } from "./hueSplit";

// The pairs tools/mockup.py's hue_split() gives, which TimeRingTest pins on the watch.
const PINS: [number, number, number][] = [
  [0xe879f9, 0x80acff, 0xff8281], // Terrain's orchid
  [0xfe4646, 0xd456db, 0xb98c00], // Activity's and Pulse's red
  [0x5cd9f0, 0x8bdba0, 0xb1c3ff], // Beacon's cyan
  [0x9aa8c0, 0x65b7bc, 0xbf97c6], // a pale custom colour, chroma floored
  [0x808080, 0xab6e64, 0x5d8e67], // a pure grey
];

describe("hueSplit", () => {
  for (const [ring, hour, minute] of PINS) {
    it(`splits ${ring.toString(16)} as the watch does`, () => {
      const { splitDegrees, splitChroma } = schema.timeRing;
      expect(hueSplit(ring, splitDegrees, splitChroma)).toEqual([hour, minute]);
    });
  }
});
