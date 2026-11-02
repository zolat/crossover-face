// On a phone the face sits above the controls, so scrolling down to them would scroll it
// away. Instead the stage sticks to the top with a negative offset, leaving a short strip
// in view, and the face shrinks into that strip as the page scrolls: the change you make
// stays visible beside the control you made it with.
//
// The face shrinks by transform, never by layout. Resizing the stage as the page scrolls
// would move the content under the finger, which moves the scroll position, which
// resizes the stage again. A transform leaves every box where it was.

/** Widths at or below this are the phone layout (styles.css's breakpoint). */
export const PHONE = "(max-width: 860px)";

/** Room above and below the shrunk face, inside the strip. */
const STRIP_PAD = 12;

export interface Measure {
  /** The face box's side at full size, and its top inside the stage. */
  face: number;
  faceTop: number;
  /** The stage's full height. */
  stage: number;
  viewportWidth: number;
  /** How far the page has scrolled the stage up: minus its top on screen. */
  scrolled: number;
}

export interface Compact {
  /** The sticky top: how far the stage may scroll away before it holds. */
  stickAt: number;
  /** Height of the strip left in view: the scroll padding for anything focused. */
  strip: number;
  /** 0 at full size, 1 fully shrunk. */
  progress: number;
  scale: number;
  /** Down by this, from the face box's own place, before scaling from its top centre. */
  shift: number;
  /** Opacity of what shares the stage with the face: it fades as the face shrinks. */
  fade: number;
}

/** The smallest the face gets: about a third of the phone's width, never more than full. */
export function smallest(face: number, viewportWidth: number): number {
  return Math.min(face, Math.max(120, Math.min(168, viewportWidth * 0.34)));
}

export function compact({ face, faceTop, stage, viewportWidth, scrolled }: Measure): Compact {
  const small = smallest(face, viewportWidth);
  const strip = small + 2 * STRIP_PAD;
  const stickAt = Math.max(0, stage - strip);
  const offset = Math.min(stickAt, Math.max(0, scrolled));
  const progress = stickAt > 0 ? offset / stickAt : 0;
  // The face's top runs from its own place to the strip's top padding, and the strip
  // starts wherever the stage has scrolled to, so the face never leaves the screen.
  const top = faceTop * (1 - progress) + STRIP_PAD * progress + offset;
  return {
    stickAt,
    strip,
    progress,
    scale: (face + (small - face) * progress) / face,
    shift: top - faceTop,
    fade: Math.max(0, 1 - 2 * progress),
  };
}

export interface CompactFace {
  /** Measure again: call after anything changes the stage's layout. */
  refresh(): void;
}

/**
 * Wire the shrinking face. `fades` share the stage and fade out as it shrinks; `enabled`
 * says when not to (holding a card to the screen to set the real size).
 */
export function compactFace(stage: HTMLElement, faceBox: HTMLElement, canvas: HTMLElement,
                            fades: HTMLElement[], enabled: () => boolean): CompactFace {
  const phone = window.matchMedia(PHONE);
  let frame = 0;

  const clear = () => {
    stage.style.top = "";
    faceBox.style.transform = "";
    canvas.classList.remove("shrunk");
    document.documentElement.style.scrollPaddingTop = "";
    for (const element of fades) {
      element.style.opacity = "";
      element.style.visibility = "";
    }
  };

  const apply = () => {
    frame = 0;
    if (!phone.matches || !enabled()) {
      clear();
      return;
    }
    const layout = compact({
      face: faceBox.offsetHeight,
      faceTop: faceBox.offsetTop,
      stage: stage.offsetHeight,
      viewportWidth: window.innerWidth,
      scrolled: -stage.getBoundingClientRect().top,
    });
    stage.style.top = `${-layout.stickAt}px`;
    document.documentElement.style.scrollPaddingTop = `${layout.strip}px`;
    faceBox.style.transform = layout.progress > 0 ? `translateY(${layout.shift}px) scale(${layout.scale})` : "";
    // Nearest-neighbour drops whole pixels when shrinking by a fraction, and a cross
    // would flicker as it scrolls; smoothing shades them all alike.
    canvas.classList.toggle("shrunk", layout.progress > 0);
    for (const element of fades) {
      element.style.opacity = layout.fade < 1 ? String(layout.fade) : "";
      element.style.visibility = layout.fade === 0 ? "hidden" : "";
    }
  };

  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(apply);
  };
  window.addEventListener("scroll", schedule, { passive: true });
  window.addEventListener("resize", schedule);
  phone.addEventListener("change", schedule);
  new ResizeObserver(schedule).observe(stage);
  schedule();
  return { refresh: schedule };
}
