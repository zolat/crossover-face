// HueSplit.pair(): two colours that read as mixing into a third, its hue turned the same
// way each side in OKLCH at its own lightness, giving up chroma where the screen cannot
// show it. The overlapping time ring's hour and minute are this split of the ring's own
// colour. Same constants and rounding as the watch and tools/mockup.py, which agree to a
// unit per channel.
import { fit, linearRgb, toByte, toOklch, wrap } from "./oklch";

/** [turned back, turned on]: the hour and the minute. Chroma floored, lightness kept. */
export function hueSplit(colour: number, degrees: number, floor: number): [number, number] {
  const [L, C, h] = toOklch(colour);
  const chroma = Math.max(C, floor);
  const side = (d: number) => {
    const hue = wrap(h + d);
    const [r, g, b] = linearRgb(L, fit(L, chroma, hue), hue);
    return (toByte(r) << 16) | (toByte(g) << 8) | toByte(b);
  };
  return [side(-degrees), side(degrees)];
}
