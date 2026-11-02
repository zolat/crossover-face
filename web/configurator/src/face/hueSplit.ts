// HueSplit.pair(): two colours that read as mixing into a third, its hue turned the same
// way each side. The overlapping time ring's hour and minute are this split of the ring's
// own colour. HSV as Python's colorsys does it, rounded half up, so the face, the mockup
// and this agree to a unit per channel.

function toHsv(colour: number): [number, number, number] {
  const r = ((colour >> 16) & 0xff) / 255;
  const g = ((colour >> 8) & 0xff) / 255;
  const b = (colour & 0xff) / 255;
  const high = Math.max(r, g, b);
  const low = Math.min(r, g, b);
  if (high === low) return [0, 0, high];
  const span = high - low;
  const rc = (high - r) / span;
  const gc = (high - g) / span;
  const bc = (high - b) / span;
  const h = r === high ? bc - gc : g === high ? 2 + rc - bc : 4 + gc - rc;
  return [wrap(h / 6), span / high, high];
}

function fromHsv(h: number, s: number, v: number): number {
  const sixth = h * 6;
  const i = Math.floor(sixth) % 6;
  const f = sixth - Math.floor(sixth);
  const p = v * (1 - s);
  const q = v * (1 - s * f);
  const t = v * (1 - s * (1 - f));
  const rgb = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i];
  return (toByte(rgb[0]) << 16) | (toByte(rgb[1]) << 8) | toByte(rgb[2]);
}

const toByte = (x: number) => Math.max(0, Math.min(255, Math.floor(x * 255 + 0.5)));
const wrap = (h: number) => ((h % 1) + 1) % 1;

/** [turned back, turned on]: the hour and the minute. Saturation floored, value kept. */
export function hueSplit(colour: number, degrees: number, floor: number): [number, number] {
  const [h, s, v] = toHsv(colour);
  const sat = Math.max(s, floor);
  const turn = degrees / 360;
  return [fromHsv(wrap(h - turn), sat, v), fromHsv(wrap(h + turn), sat, v)];
}
