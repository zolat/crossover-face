import { describe, expect, it } from "vitest";
import { compact, smallest } from "./compact";

// A 390-wide phone: a 358px face box under the pills, in a 520px stage.
const phone = { face: 358, faceTop: 56, stage: 520, viewportWidth: 390 };

describe("the shrinking face", () => {
  it("is untouched at the top of the page", () => {
    const layout = compact({ ...phone, scrolled: 0 });
    expect(layout).toMatchObject({ progress: 0, scale: 1, shift: 0, fade: 1 });
  });

  it("holds at its smallest once the stage has scrolled as far as it may", () => {
    const small = smallest(358, 390);
    expect(small).toBeCloseTo(132.6);
    for (const scrolled of [phone.stage, 5000]) {
      const layout = compact({ ...phone, scrolled });
      expect(layout.progress).toBe(1);
      expect(layout.scale * phone.face).toBeCloseTo(small);
      expect(layout.fade).toBe(0);
      // The face's top lands at the strip's padding, just inside the screen.
      expect(phone.faceTop + layout.shift - layout.stickAt).toBeCloseTo(12);
      expect(layout.strip).toBeCloseTo(small + 24);
      expect(layout.stickAt).toBeCloseTo(phone.stage - layout.strip);
    }
  });

  it("never leaves the screen, and only ever shrinks, on the way", () => {
    let last = Infinity;
    for (let scrolled = 0; scrolled <= 600; scrolled += 7) {
      const layout = compact({ ...phone, scrolled });
      const onScreenTop = phone.faceTop + layout.shift - Math.min(scrolled, layout.stickAt);
      const size = layout.scale * phone.face;
      expect(onScreenTop).toBeGreaterThanOrEqual(0);
      expect(size).toBeLessThanOrEqual(last + 1e-9);
      last = size;
    }
  });

  it("does not grow a face that is already small, as at real size", () => {
    const layout = compact({ face: 100, faceTop: 56, stage: 300, viewportWidth: 390, scrolled: 1000 });
    expect(layout.scale).toBe(1);
  });
});
