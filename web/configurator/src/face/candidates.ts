// Duo-tone candidates: themes of two colours, alternating ring by ring, offered beside the
// shipping themes so they can be judged on the page and on the wrist before any of them
// earns a persisted theme ID. A candidate is a custom theme (ID 99) with these colours, so
// the code it makes already carries it to the watch; nothing on the watch knows its name.
//
// Two colours because five, plus the colour the data itself brings (the temperature ramp,
// sun dots, the time ring's split, block levels), had made every theme busy. Alternating
// keeps each ring apart from its neighbours with only one pair to get right.
//
// The temperature ramp has only two hues to run between: cold is the bluer of the two, by
// the rule a random theme's ramp uses, and both upper stops are the warmer, so the ramp
// turns over the first half of the scale, 0 to 30°C where most days are, and holds there.
import { type RandomTheme, rampFor } from "./randomTheme";

export interface Candidate {
  name: string;
  /** The outer ring's colour, then the one beside it. */
  pair: [number, number];
}

export const CANDIDATES: readonly Candidate[] = [
  { name: "Ember & Ice", pair: [0xff7a3d, 0x6fd3ff] },
  { name: "Orchid & Lime", pair: [0xe879f9, 0xb8d64b] },
  { name: "Coral & Teal", pair: [0xff6f61, 0x2fd9c5] },
  { name: "Gold & Indigo", pair: [0xf2b33d, 0x8e7bff] },
  { name: "Rose & Mint", pair: [0xff5c9a, 0x5cf2b0] },
  { name: "Lemon & Azure", pair: [0xf0dc50, 0x3d9bff] },
  { name: "Emerald & Violet", pair: [0x3fe08a, 0xb07cff] },
  { name: "Chartreuse & Fuchsia", pair: [0xa8e63d, 0xff4fb8] },
  { name: "Lagoon", pair: [0x2fd9c5, 0x5c8fff] },
  { name: "Dusk", pair: [0xff6b7a, 0xd67cff] },
];

/** A candidate as the five colours and three stops a custom theme carries. */
export function duoTone({ pair: [outer, beside] }: Candidate): RandomTheme {
  const colours: RandomTheme["colours"] = [outer, beside, outer, beside, outer];
  const cold = rampFor([outer, beside])[0];
  // Stops index ring slots: the cold colour's first slot, then the warm colour's two.
  const ramp: RandomTheme["ramp"] = cold === 0 ? [0, 1, 3] : [1, 0, 2];
  return { colours, ramp };
}

/** The candidate a custom theme is showing, if it is one. */
export function candidateFor(colours: readonly number[], ramp: readonly number[]): Candidate | null {
  return CANDIDATES.find((candidate) => {
    const theme = duoTone(candidate);
    return theme.colours.every((colour, i) => colours[i] === colour) && theme.ramp.every((stop, i) => ramp[i] === stop);
  }) ?? null;
}
