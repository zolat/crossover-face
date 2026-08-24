"""Measure a rendered watch face against Garmin's AMOLED always-on budget.

Garmin blanks the screen if an always-on watch face exceeds 10% of the screen's
luminance. This measures the same quantity the hardware cares about: mean
relative luminance over the circular screen area, as a fraction of full white.

Usage:  python3 tools/luminance.py face.png [...]
"""

from __future__ import annotations

import sys

from PIL import Image

BUDGET = 0.10

# Rec. 709 luma coefficients — the standard relative-luminance weighting.
_R, _G, _B = 0.2126, 0.7152, 0.0722


def measure(img: Image.Image) -> float:
    """Mean relative luminance of a square face image, 0.0-1.0.

    Only pixels inside the inscribed circle count: the corners of a square
    render are not part of a round display and would dilute the average.
    """
    img = img.convert("RGB")
    w, h = img.size
    cx, cy, r2 = (w - 1) / 2.0, (h - 1) / 2.0, (min(w, h) / 2.0) ** 2

    px = img.load()
    total = 0.0
    count = 0
    for y in range(h):
        dy2 = (y - cy) ** 2
        for x in range(w):
            if (x - cx) ** 2 + dy2 > r2:
                continue
            r, g, b = px[x, y]
            total += (_R * r + _G * g + _B * b) / 255.0
            count += 1
    return total / count if count else 0.0


def verdict(fraction: float) -> str:
    pct = fraction * 100.0
    mark = "OK " if fraction <= BUDGET else "OVER"
    return f"{mark} {pct:5.2f}%  (budget {BUDGET * 100:.0f}%)"


def main(paths: list[str]) -> int:
    if not paths:
        print(__doc__)
        return 2
    over = 0
    for path in paths:
        with Image.open(path) as img:
            fraction = measure(img)
        if fraction > BUDGET:
            over += 1
        print(f"{verdict(fraction)}  {path}")
    return 1 if over else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
