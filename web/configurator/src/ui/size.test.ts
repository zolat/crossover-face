import { describe, expect, it } from "vitest";
import { faceSize } from "./size";

describe("face size", () => {
  it("snaps a large face to whole device pixels per watch pixel", () => {
    // 700 CSS px at 2x is 1400 device px: three per watch pixel at 390, so 585 CSS px.
    expect(faceSize("fit", 700, 2, 390, 30.48, 5)).toEqual({ css: 585, backing: 3, smooth: false });
  });

  it("fills the box from a whole-number copy when snapping would cost too much", () => {
    // A phone: 358 CSS px at 3x snaps to 260, so draw 3x and bring it down smoothly.
    expect(faceSize("fit", 358, 3, 390, 30.48, 5)).toEqual({ css: 358, backing: 3, smooth: true });
  });

  it("draws real size from the diameter and the calibration", () => {
    expect(faceSize("actual", 700, 2, 390, 30.48, 5)).toEqual({ css: 152.4, backing: 1, smooth: true });
    expect(faceSize("actual", 700, 2, 390, 30.48, 390 / 2 / 30.48)).toEqual({ css: 195, backing: 1, smooth: false });
  });
});
