// Draw the face at the watch's own resolution, pixel for pixel.
//
// Crosses are written straight into an ImageData the size of the screen and the canvas
// is upscaled with nearest-neighbour, so what the page shows is the nine pixels per dot
// the watch lights — not an anti-aliased impression of them.
//
// What it draws: every dot in its tier for the chosen sources (sample readings), the
// temperature ramp, the current-temperature mark, sun dots, forecast blocks and, awake,
// the date's outline, and the time ring a watch with drawn hands carries, at a sample
// time. What it does not: hands or a lap past the goal.
import type { Config } from "../codec/configCode";
import { cellLit, cellOf, dimmed, gap, GLYPH_COLS, LINE_PERCENTS, origin, outline } from "./date";
import type { Lattice } from "./lattice";
import type { BuiltPalette } from "./palette";
import { inSpan, readingFor } from "./samples";
import { effectiveRings, isTime, SAMPLE_TIME, timeColours, timeFractions, timeSlot } from "./rings";
import { isTemperatureRange, schema } from "./schema";

export type Mode = "awake" | "alwaysOn";

const HOURS = 12;
const BAND_COUNT = 3;
const LEVELS = 15;
const BLOCK = 22.5 / 360;
const LEAD = (30 / 360 - BLOCK) / 2;

/** Inner and outer radius of a ring, from the exported integer edges. */
function ringRadii(lattice: Lattice, ring: number): [number, number] {
  return [lattice.ringEdges[ring], ring === 0 ? lattice.radius : lattice.ringEdges[ring - 1]];
}

type Tier = "band" | "weak" | "dim";

/** Which tier a dot takes inside a forecast block, as HourBands fills it. */
export function blockTier(lattice: Lattice, ring: number, dx: number, dy: number, turn: number,
                   blocks: (number | null)[]): Tier {
  const slot = Math.floor(turn * HOURS) % HOURS;
  const along = turn - slot / HOURS - LEAD;
  if (along < 0 || along >= BLOCK) return "weak"; // the gutter round the hour mark
  const level = blocks[slot];
  if (level === null) return "dim";
  const [inner, outer] = ringRadii(lattice, ring);
  const thickness = Math.trunc((outer - inner) / BAND_COUNT);
  const radius = Math.hypot(dx, dy);
  const band = Math.min(BAND_COUNT - 1, Math.floor((radius - inner) / thickness));
  const filled = (level * BAND_COUNT) / LEVELS;
  const whole = Math.floor(filled);
  if (band < whole) return "band";
  if (band === whole) {
    // HourBands.partialHalfOn(): a partial band never narrower than the ring's floor.
    const floor = schema.sources.blockWindowFloor[ring] / HOURS;
    const window = ((filled - whole) * BLOCK) / 2;
    const half = window > 0 && window < floor ? floor : window;
    if (Math.abs(along - BLOCK / 2) < half) return "band";
  }
  return "weak";
}

interface Solid {
  dx: number;
  dy: number;
  colour: number;
}

/**
 * `day` is the day of the month the date shows; the setting decides whether it does.
 * `drawnHands` is the watch's: one with drawn hands tells the time in a ring.
 */
export function render(image: ImageData, lattice: Lattice, palette: BuiltPalette, config: Config, mode: Mode,
                       day: number | null = null, drawnHands = false): void {
  const { data, width } = image;
  data.fill(0);
  for (let i = 3; i < data.length; i += 4) data[i] = 255;
  const scale = width / lattice.screen;
  const centre = lattice.screen / 2;
  const put = (x: number, y: number, colour: number) => {
    // A dot sits on integer pixels at native scale; at any other scale fill the block.
    for (let sy = 0; sy < scale; sy++) {
      for (let sx = 0; sx < scale; sx++) {
        const px = Math.round(x * scale) + sx;
        const py = Math.round(y * scale) + sy;
        if (px < 0 || py < 0 || px >= width || py >= width) continue;
        const at = (py * width + px) * 4;
        data[at] = (colour >> 16) & 255;
        data[at + 1] = (colour >> 8) & 255;
        data[at + 2] = colour & 255;
      }
    }
  };

  const alwaysOn = mode === "alwaysOn";
  const heldBack = alwaysOn && config.alwaysOnFill === 1;
  const sources = effectiveRings(config, drawnHands, lattice.ringCounts.length);
  const readings = sources.map((source) => readingFor(source, alwaysOn));
  const [hourEnd, minuteEnd] = timeFractions(SAMPLE_TIME.hour, SAMPLE_TIME.minute);
  // TimeRing's split edge: the innermost sub-band's outer edge, integer like DotGrid's.
  const timeEdgeSq = sources.map((_, ring) => {
    const [inner, outer] = ringRadii(lattice, ring);
    const edge = inner + Math.trunc((outer - inner) / BAND_COUNT);
    return edge * edge;
  });
  const solids: Solid[] = [];
  // Awake only, as on the watch: always-on carries no date.
  const dating = day !== null && !alwaysOn && config.showDate === 1;
  const glyphDay = day ?? 0;
  const glyphColours = new Map<number, number>();

  for (const [dx, dy, ring, orientation, turn] of lattice.dots) {
    const tiers = palette.rings[ring];
    const reading = readings[ring];
    const source = sources[ring];
    let colour: number;
    if (isTime(source)) {
      // In every power mode, held back or not: the time is not data.
      colour = timeColours(source, tiers)[timeSlot(source, dx * dx + dy * dy, timeEdgeSq[ring], turn, hourEnd, minuteEnd)];
    } else if (heldBack) {
      colour = tiers.weakHeldBack;
    } else if (reading.blocks) {
      const tier = blockTier(lattice, ring, dx, dy, turn, reading.blocks);
      colour = tier === "band" ? (alwaysOn ? tiers.bandAlwaysOn : tiers.band)
             : tier === "dim" ? tiers.dim
             : alwaysOn ? tiers.weakAlwaysOn : tiers.weak;
    } else if (reading.span && inSpan(turn, reading.span)) {
      colour = isTemperatureRange(source)
        ? palette.ramp[Math.trunc(turn * (palette.ramp.length - 1))]
        : alwaysOn ? tiers.bandAlwaysOn : tiers.band;
    } else {
      colour = alwaysOn ? tiers.weakAlwaysOn : tiers.weak;
    }
    if (dating) {
      const cell = cellOf(lattice, dx, dy);
      if (cell !== null && cellLit(glyphDay, cell % GLYPH_COLS, Math.floor(cell / GLYPH_COLS))) glyphColours.set(cell, colour);
    }
    const [ax, ay, bx, by] = lattice.arms[config.dotRotation === 1 ? 0 : orientation];
    const x = centre + dx;
    const y = centre + dy;
    for (let k = -2; k <= 2; k++) {
      put(x + step(k * ax), y + step(k * ay), colour);
      put(x + step(k * bx), y + step(k * by), colour);
    }
  }

  // Marks and sun dots are solid DOT x DOT blocks, placed on the dot nearest their
  // position — mid-ring for the mark, sunrise on the ring's inner edge and sunset on
  // its outer one (DotGrid's sun placement).
  if (!heldBack) {
    readings.forEach((reading, ring) => {
      const tiers = palette.rings[ring];
      const [inner, outer] = ringRadii(lattice, ring);
      if (reading.mark !== undefined) {
        const spot = nearestDot(lattice, ring, reading.mark, (inner + outer) / 2);
        if (spot) solids.push({ ...spot, colour: tiers.softMark });
      }
      if (reading.sun) {
        const rise = nearestDot(lattice, ring, reading.sun[0], inner);
        const set = nearestDot(lattice, ring, reading.sun[1], outer);
        if (rise) solids.push({ ...rise, colour: tiers.sunrise });
        if (set) solids.push({ ...set, colour: tiers.sunset });
      }
    });
  }
  const half = Math.floor(lattice.dot / 2);
  for (const solid of solids) {
    for (let y = -half; y <= half; y++) {
      for (let x = -half; x <= half; x++) put(centre + solid.dx + x, centre + solid.dy + y, solid.colour);
    }
  }

  // The outline goes in after the dots, in the colour of the dot each line leaves from.
  if (dating) {
    const percent = LINE_PERCENTS[config.dateOutline] ?? LINE_PERCENTS[1];
    const { from, length } = gap(lattice);
    const [col0, row0] = origin(lattice);
    const half = ((lattice.cols - 1) * lattice.pitch) / 2;
    for (const [a, b] of outline(glyphDay)) {
      const colour = glyphColours.get(a);
      if (colour === undefined) continue;
      const line = dimmed(colour, percent);
      const x = centre + (col0 + (a % GLYPH_COLS)) * lattice.pitch - half;
      const y = centre + (row0 + Math.floor(a / GLYPH_COLS)) * lattice.pitch - half;
      for (let k = 0; k < length; k++) {
        if (b === a + 1) put(x + from + k, y, line);
        else put(x, y + from + k, line);
      }
    }
  }
}

/** Half an arm offset, rounded away from zero on both sides so a cross stays symmetric. */
const step = (twice: number) => Math.sign(twice) * Math.round(Math.abs(twice) / 2);

function nearestDot(lattice: Lattice, ring: number, turn: number, radius: number): { dx: number; dy: number } | null {
  const angle = turn * 2 * Math.PI;
  const tx = Math.sin(angle) * radius;
  const ty = -Math.cos(angle) * radius;
  let best: { dx: number; dy: number } | null = null;
  let bestDist = Infinity;
  for (const [dx, dy, dotRing] of lattice.dots) {
    if (dotRing !== ring) continue;
    const dist = (dx - tx) ** 2 + (dy - ty) ** 2;
    if (dist < bestDist) {
      bestDist = dist;
      best = { dx, dy };
    }
  }
  return best;
}
