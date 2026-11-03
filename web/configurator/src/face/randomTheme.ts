// A random custom theme that is still a good one: five hues spread round the wheel by
// one of a few schemes, bright enough to show in always-on and not so pale that a lap
// past the goal disappears, with neighbouring rings clearly apart. A draw that any of
// themeWarnings() would flag, or with a colour the picker hides as dull, is thrown away
// and drawn again.
//
// The temperature ramp follows the colours: cold takes the hue nearest blue, hot the one
// nearest red, the middle the one nearest yellow of what is left.
import { isDull } from "./dull";
import { build } from "./palette";
import { distance, themeWarnings } from "./warnings";

export interface RandomTheme {
  /** Five, outermost first; the fifth is the 51mm's centre ball. */
  colours: [number, number, number, number, number];
  ramp: [number, number, number];
}

type Random = () => number;

/**
 * Hue offsets, in degrees, for five colours. Each is shuffled across the rings, so every
 * pair is kept at least 45 degrees apart: any two may end up neighbours.
 */
const SCHEMES = [
  [0, 72, 144, 216, 288], // pentagon
  [0, 60, 150, 210, 300], // two pairs and an accent
  [0, 90, 150, 240, 300], // square, split
  [0, 45, 120, 200, 280], // a near pair and a spread
  [0, 100, 160, 220, 300], // an accent and a run
];

/** Neighbours this far apart read clearly; themeWarnings' floor is only 15. */
const SPREAD = 28;
const ATTEMPTS = 200;

const between = (random: Random, low: number, high: number) => low + random() * (high - low);

export function hsl(hue: number, saturation: number, lightness: number): number {
  const c = (1 - Math.abs(2 * lightness - 1)) * saturation;
  const h = (((hue % 360) + 360) % 360) / 60;
  const x = c * (1 - Math.abs((h % 2) - 1));
  const [r, g, b] = h < 1 ? [c, x, 0] : h < 2 ? [x, c, 0] : h < 3 ? [0, c, x] : h < 4 ? [0, x, c] : h < 5 ? [x, 0, c] : [c, 0, x];
  const m = lightness - c / 2;
  const to = (v: number) => Math.round((v + m) * 255);
  return (to(r) << 16) | (to(g) << 8) | to(b);
}

function hueOf(colour: number): number {
  const r = ((colour >> 16) & 255) / 255;
  const g = ((colour >> 8) & 255) / 255;
  const b = (colour & 255) / 255;
  const max = Math.max(r, g, b);
  const d = max - Math.min(r, g, b);
  if (d === 0) return 0;
  const h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return (h * 60 + 360) % 360;
}

const arc = (a: number, b: number) => Math.min(Math.abs(a - b), 360 - Math.abs(a - b));

function nearest(hues: number[], target: number, taken: number[]): number {
  let best = -1;
  for (let ring = 0; ring < hues.length; ring++) {
    if (taken.includes(ring)) continue;
    if (best < 0 || arc(hues[ring], target) < arc(hues[best], target)) best = ring;
  }
  return best;
}

export function rampFor(colours: number[]): [number, number, number] {
  const hues = colours.map(hueOf);
  const cold = nearest(hues, 215, []);
  const hot = nearest(hues, 5, [cold]);
  const mid = nearest(hues, 50, [cold, hot]);
  return [cold, mid, hot];
}

function draw(random: Random): RandomTheme {
  const base = random() * 360;
  const scheme = [...SCHEMES[Math.floor(random() * SCHEMES.length)]];
  for (let i = scheme.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [scheme[i], scheme[j]] = [scheme[j], scheme[i]];
  }
  const colours = scheme.map((offset) =>
    hsl(base + offset + between(random, -12, 12), between(random, 0.55, 0.85), between(random, 0.56, 0.72)),
  ) as RandomTheme["colours"];
  return { colours, ramp: rampFor(colours) };
}

export function isGood(theme: RandomTheme): boolean {
  if (themeWarnings(build(theme)).length > 0) return false;
  if (theme.colours.some((colour) => isDull(colour))) return false;
  for (let ring = 0; ring + 1 < theme.colours.length; ring++) {
    if (distance(theme.colours[ring], theme.colours[ring + 1]) < SPREAD) return false;
  }
  return true;
}

export function randomTheme(random: Random = Math.random): RandomTheme {
  let theme = draw(random);
  for (let attempt = 1; attempt < ATTEMPTS && !isGood(theme); attempt++) theme = draw(random);
  return theme;
}
