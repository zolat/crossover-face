// How big the face is drawn: as large as the page allows, or at the watch's real size.
//
// A nearest-neighbour upscale by 3.6 draws some arm pixels three wide and some four,
// which reads as some crosses being dimmer than others. So the face is never stretched
// by a fraction: it is copied up by a whole number into the canvas, then either shown
// at exactly that size (crisp) or brought down to the size wanted with smoothing, which
// shades every pixel the same way.
//
// A browser cannot know how many CSS pixels make a millimetre — its "1in" is 96px
// whatever the screen — so real size starts from an estimate and is set exactly by
// holding a bank card (ISO/IEC 7810 ID-1, 85.60 x 53.98 mm) to the screen.

export type View = "fit" | "actual";

export const CARD_MM = { width: 85.6, height: 53.98 } as const;
const STORAGE_KEY = "crossover-face-px-per-mm";

/** A first guess: Retina Macs run near 120 CSS px an inch, everything else near 96. */
export function estimatedPxPerMm(devicePixelRatio: number): number {
  return (devicePixelRatio >= 2 ? 120 : 96) / 25.4;
}

/** The viewer's calibration, if they have made one. Per-viewer, and optional. */
export const calibration = {
  load(): number | null {
    try {
      const value = Number(localStorage.getItem(STORAGE_KEY));
      return Number.isFinite(value) && value > 1 ? value : null;
    } catch {
      return null;
    }
  },
  save(pxPerMm: number) {
    try {
      localStorage.setItem(STORAGE_KEY, String(pxPerMm));
    } catch {
      // Blocked storage: the calibration holds for this visit only.
    }
  },
};

export interface FaceSize {
  /** CSS pixels across. */
  css: number;
  /** Canvas pixels per watch pixel. */
  backing: number;
  /** Whether the canvas is scaled to fit, rather than shown pixel for pixel. */
  smooth: boolean;
}

/** Large gives up a little size for crispness, but not more than this share. */
const SNAP_KEEPS = 0.8;

export function faceSize(view: View, box: number, devicePixelRatio: number, screen: number,
                         displayMm: number, pxPerMm: number): FaceSize {
  let css = displayMm * pxPerMm;
  if (view === "fit") {
    const whole = Math.floor((box * devicePixelRatio) / screen);
    const snapped = (whole * screen) / devicePixelRatio;
    css = whole >= 2 && snapped >= SNAP_KEEPS * box ? snapped : box;
  }
  const device = Math.round(css * devicePixelRatio);
  const backing = Math.max(1, Math.ceil(device / screen));
  return { css, backing, smooth: backing * screen !== device };
}
