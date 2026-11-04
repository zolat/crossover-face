// Palette.build(), ported. Monkey C does this arithmetic in 32-bit floats and truncates,
// so every step here goes through Math.fround: a channel that lands on 109.99999 on the
// watch must land there here too, or the preview is a shade off from the face.
import { lighten } from "./oklch";
import { schema, type Theme } from "./schema";

const P = schema.palette;
const f = Math.fround;

export const channel = (colour: number, shift: number) => (colour >> shift) & 0xff;

export function mix(from: number, to: number, amount: number): number {
  const a = f(amount);
  const part = (shift: number) => {
    const start = channel(from, shift);
    return Math.trunc(f(start + f((channel(to, shift) - start) * a)));
  };
  return (part(16) << 16) | (part(8) << 8) | part(0);
}

export function scale(colour: number, factor: number): number {
  const k = f(factor);
  const part = (shift: number) => Math.min(0xff, Math.max(0, Math.trunc(f(channel(colour, shift) * k))));
  return (part(16) << 16) | (part(8) << 8) | part(0);
}

export interface RingTiers {
  band: number;
  weak: number;
  bandAlwaysOn: number;
  weakAlwaysOn: number;
  weakHeldBack: number;
  dim: number;
  over: number;
  marker: number;
  softMark: number;
  sunrise: number;
  sunset: number;
}

export interface BuiltPalette {
  rings: RingTiers[];
  ramp: number[];
}

/**
 * The colours and three stops a theme draws with, shipping or custom. Shipping themes
 * have five colours; a custom theme from a version-1 code has four, and gains the
 * watch's default fifth (StatMap.readCustomTheme) for the 51mm's centre ball.
 */
export interface ThemeColours {
  colours: readonly number[];
  ramp: readonly number[];
}

export function themeColours(theme: number, custom: ThemeColours): ThemeColours {
  if (theme === schema.themeCustom) return custom;
  const found: Theme | undefined = schema.themes.find((entry) => entry.id === theme);
  return found ?? schema.themes[0];
}

/**
 * The theme always-on draws from at a boost level: Palette.boosted(). Building a
 * palette from it gives every always-on tier the watch draws — filled, unfilled,
 * held back, unknown hours, marks, sun dots, the ramp and the time ring's split.
 */
export function boostedTheme(theme: ThemeColours, level: number): ThemeColours {
  const amount = P.BOOST_AMOUNTS[level] ?? 0;
  if (amount === 0) return theme;
  return { colours: theme.colours.map((colour) => lighten(colour, amount)), ramp: theme.ramp };
}

export function build(theme: ThemeColours): BuiltPalette {
  const colours = theme.colours.length >= 5 ? theme.colours : [...theme.colours, schema.customFifthDefault];
  const rings = colours.map((colour): RingTiers => {
    const lifted = scale(colour, P.LIFT);
    return {
      band: colour,
      weak: scale(colour, P.WEAK_ACTIVE),
      bandAlwaysOn: lifted,
      weakAlwaysOn: scale(lifted, P.WEAK_ALWAYS_ON),
      weakHeldBack: scale(colour, P.WEAK_HELD_BACK),
      dim: scale(colour, P.WEAK_UNKNOWN),
      over: mix(P.MARKER, colour, P.OVER_TINT),
      marker: mix(P.MARKER, colour, P.MARKER_TINT),
      softMark: mix(P.MARKER, colour, P.SOFT_MARK_TINT),
      sunrise: mix(P.SUN_HUES[0], colour, P.SUN_TINT),
      sunset: mix(P.SUN_HUES[1], colour, P.SUN_TINT),
    };
  });
  const [cold, mid, hot] = theme.ramp.map((stop) => theme.colours[stop % 4]);
  const ramp: number[] = [];
  for (let step = 0; step < P.RAMP_STEPS; step++) {
    const along = f(f(step) / (P.RAMP_STEPS - 1));
    ramp.push(along <= 0.5 ? mix(cold, mid, f(along * 2)) : mix(mid, hot, f(f(along - 0.5) * 2)));
  }
  return { rings, ramp };
}

export const hex = (colour: number) => "#" + colour.toString(16).padStart(6, "0");
export const fromHex = (text: string) => parseInt(text.replace(/^#/, ""), 16) & 0xffffff;
