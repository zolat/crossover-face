// OKLCH, the perceptual space the face's colour maths runs in: HueSplit on the watch and
// in tools/mockup.py, the time ring's split and the dull-colour floor here. Same constants
// and rounding as the watch, which the hue split's pins hold to a unit per channel.

export type Lch = [number, number, number];

const linear = (c: number) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const cbrt = (x: number) => (x <= 0 ? 0 : x ** (1 / 3));

export function toOklch(colour: number): Lch {
  const r = linear(((colour >> 16) & 0xff) / 255);
  const g = linear(((colour >> 8) & 0xff) / 255);
  const b = linear((colour & 0xff) / 255);
  const l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
  const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  const B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
  return [L, Math.hypot(A, B), wrap((Math.atan2(B, A) * 180) / Math.PI)];
}

export function linearRgb(L: number, C: number, h: number): Lch {
  const a = C * Math.cos((h * Math.PI) / 180);
  const b = C * Math.sin((h * Math.PI) / 180);
  const l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (L - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
}

export const inGamut = (rgb: Lch) => rgb.every((x) => x >= -1e-4 && x <= 1 + 1e-4);

export function fit(L: number, C: number, h: number): number {
  if (inGamut(linearRgb(L, C, h))) return C;
  let low = 0;
  let high = C;
  for (let i = 0; i < 24; i++) {
    const mid = (low + high) / 2;
    if (inGamut(linearRgb(L, mid, h))) low = mid;
    else high = mid;
  }
  return low;
}

export function toByte(x: number): number {
  const c = Math.min(1, Math.max(0, x));
  const encoded = c <= 0.0031308 ? 12.92 * c : 1.055 * c ** (1 / 2.4) - 0.055;
  return Math.max(0, Math.min(255, Math.floor(encoded * 255 + 0.5)));
}

export const wrap = (h: number) => ((h % 360) + 360) % 360;

/** An sRGB 0xRRGGBB for OKLCH, giving up chroma where the screen cannot show it. */
export function fromOklch(L: number, C: number, h: number): number {
  const [r, g, b] = linearRgb(L, fit(L, C, h), h);
  return (toByte(r) << 16) | (toByte(g) << 8) | toByte(b);
}
