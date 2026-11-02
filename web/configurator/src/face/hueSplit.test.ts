import { describe, expect, it } from "vitest";
import { schema } from "./schema";
import { hueSplit } from "./hueSplit";

// The pairs tools/mockup.py's hue_split() gives, which TimeRingTest pins on the watch.
const PINS: [number, number, number][] = [
  [0xe879f9, 0x6477f9, 0xf96477], // Terrain's orchid
  [0xfe4646, 0xfe46fe, 0xfefe46], // Activity's and Pulse's red
  [0x5cd9f0, 0x5cf073, 0x735cf0], // Beacon's cyan
  [0x9aa8c0, 0x4dc096, 0x964dc0], // a pale custom colour, saturation floored
];

describe("hueSplit", () => {
  for (const [ring, hour, minute] of PINS) {
    it(`splits ${ring.toString(16)} as the watch does`, () => {
      const { splitDegrees, splitSaturation } = schema.timeRing;
      expect(hueSplit(ring, splitDegrees, splitSaturation)).toEqual([hour, minute]);
    });
  }
});
