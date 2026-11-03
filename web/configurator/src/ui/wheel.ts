// One colour wheel for the custom theme: hue round it, clockwise from red at twelve (the
// way every ring fills), saturation out from the centre, brightness on a slider below.
// With dull colours hidden, the part of the wheel too dark or too grey to read on the
// watch is shaded and cannot be picked: a pick there lands on the nearest lively colour.
//
// The wheel keeps its own hue, saturation and brightness while it is used, because a
// colour does not carry them back (a grey has no hue), and only re-reads them from a
// colour that came from somewhere else.
import { type Floor, DULL, fromHsv, type Hsv, isDull, lively, toHsv } from "../face/dull";
import { fromHex, hex } from "../face/palette";
import { h, uid } from "./dom";

export interface Wheel {
  element: HTMLElement;
  /** Show a colour chosen elsewhere: another ring, Randomise, a pasted code. */
  show(colour: number, label: string): void;
}

interface Options {
  colour: number;
  label: string;
  hideDull: boolean;
  onPick(colour: number): void;
  onHideDull(hide: boolean): void;
  floor?: Floor;
}

const SIZE = 232;
/** How bright a hidden colour is drawn: there, but plainly not on offer. */
const SHADE = 0.16;
const TRACK_STOPS = 24;

export function colourWheel(options: Options): Wheel {
  const floor = options.floor ?? DULL;
  let hideDull = options.hideDull;
  let point: Hsv = toHsv(options.colour);
  let shown = options.colour;
  let label = options.label;

  const disc = h("canvas", {
    class: "wheel-disc", tabindex: 0, role: "slider", "data-key": "wheel",
    "aria-valuemin": 0, "aria-valuemax": 360,
  });
  const brightnessId = uid("brightness");
  const brightness = h("input", {
    id: brightnessId, type: "range", min: 0, max: 100, step: 1, "data-key": "brightness",
    oninput: () => pick([point[0], point[1], Number(brightness.value) / 100], "v"),
  });
  const hexId = uid("hex");
  const hexInput = h("input", {
    id: hexId, type: "text", class: "hex", "data-key": "colour-hex", spellcheck: "false", autocomplete: "off",
    maxlength: 7, "aria-label": "Colour as hex",
    onchange: () => {
      const text = hexInput.value.trim().replace(/^#?/, "#");
      if (!/^#[0-9a-f]{6}$/i.test(text)) {
        hexInput.value = hex(shown);
        return;
      }
      const typed = toHsv(fromHex(text));
      const kept = hideDull ? lively(typed, "s", floor) : typed;
      pick(kept, "s", fromHsv(kept) !== fromHex(text) ? `${text} is too dull to see on the watch, so it was brightened.` : "");
    },
  });
  const hide = h("input", {
    type: "checkbox", id: uid("hide-dull"), "data-key": "hide-dull", checked: hideDull,
    onchange: () => {
      hideDull = hide.checked;
      options.onHideDull(hideDull);
      paintDisc();
      paintTrack();
      describe("");
    },
  });
  const note = h("p", { class: "hint wheel-note", "aria-live": "polite" });

  const element = h("div", { class: "wheel" },
    disc,
    h("div", { class: "brightness" }, h("label", { for: brightnessId }, "Brightness"), brightness),
    h("div", { class: "wheel-row" },
      hexInput,
      h("label", { class: "check" }, hide, "Hide dull colours")),
    note);

  // --- drawing -------------------------------------------------------------

  const scale = Math.min(2, Math.max(1, Math.round(window.devicePixelRatio || 1)));
  const side = SIZE * scale;
  disc.width = disc.height = side;
  const context = disc.getContext("2d");
  let image: ImageData | null = null;
  let imageKey = "";

  function at(x: number, y: number): [number, number] {
    const r = side / 2;
    const dx = x - r;
    const dy = y - r;
    const hue = ((Math.atan2(dx, -dy) * 180) / Math.PI + 360) % 360;
    return [hue, Math.min(1, Math.hypot(dx, dy) / r)];
  }

  function paintDisc() {
    if (!context) return;
    const key = `${point[2]}|${hideDull}`;
    if (key !== imageKey || !image) {
      image = context.createImageData(side, side);
      const r = side / 2;
      for (let y = 0; y < side; y++) {
        for (let x = 0; x < side; x++) {
          const distance = Math.hypot(x + 0.5 - r, y + 0.5 - r);
          if (distance > r) continue;
          const [hue, s] = at(x + 0.5, y + 0.5);
          const colour = fromHsv([hue, s, point[2]]);
          const k = hideDull && isDull(colour, floor) ? SHADE : 1;
          const i = (y * side + x) * 4;
          image.data[i] = ((colour >> 16) & 255) * k;
          image.data[i + 1] = ((colour >> 8) & 255) * k;
          image.data[i + 2] = (colour & 255) * k;
          image.data[i + 3] = Math.round(255 * Math.min(1, r - distance + 0.5));
        }
      }
      imageKey = key;
    }
    context.putImageData(image, 0, 0);
    // The marker: a ring in black and white, so it shows on any colour.
    const r = side / 2;
    const angle = (point[0] * Math.PI) / 180;
    const x = r + Math.sin(angle) * point[1] * r;
    const y = r - Math.cos(angle) * point[1] * r;
    context.lineWidth = 2 * scale;
    context.strokeStyle = "#000";
    context.beginPath();
    context.arc(x, y, 9 * scale, 0, Math.PI * 2);
    context.stroke();
    context.strokeStyle = "#fff";
    context.beginPath();
    context.arc(x, y, 7 * scale, 0, Math.PI * 2);
    context.stroke();
  }

  /** The slider's track is the brightness range at this hue and saturation, dull shaded. */
  function paintTrack() {
    const stops: string[] = [];
    for (let i = 0; i <= TRACK_STOPS; i++) {
      const v = i / TRACK_STOPS;
      const colour = fromHsv([point[0], point[1], v]);
      const k = hideDull && isDull(colour, floor) ? SHADE : 1;
      const channel = (shift: number) => Math.round(((colour >> shift) & 255) * k);
      stops.push(`rgb(${channel(16)} ${channel(8)} ${channel(0)}) ${((v * 100).toFixed(1))}%`);
    }
    brightness.style.setProperty("--track", `linear-gradient(90deg, ${stops.join(", ")})`);
  }

  function describe(message: string) {
    const dull = isDull(shown, floor);
    note.textContent = message || (dull
      ? "This colour is dull, so it may be hard to see on the watch."
      : hideDull ? "Colours too dark or too grey to see on the watch are shaded out." : "");
    disc.setAttribute("aria-valuenow", String(Math.round(point[0])));
    disc.setAttribute("aria-valuetext", `${hex(shown)}, hue ${Math.round(point[0])} degrees, ${Math.round(point[1] * 100)}% colourful`);
  }

  function sync(message = "") {
    disc.setAttribute("aria-label", `${label}: hue and colourfulness`);
    brightness.value = String(Math.round(point[2] * 100));
    if (document.activeElement !== hexInput) hexInput.value = hex(shown);
    paintDisc();
    paintTrack();
    describe(message);
  }

  // --- picking -------------------------------------------------------------

  function pick(next: Hsv, axis: "s" | "v", message = "") {
    point = hideDull ? lively(next, axis, floor) : next;
    const colour = fromHsv(point);
    const changed = colour !== shown;
    shown = colour;
    hexInput.value = hex(shown);
    sync(message);
    if (changed) options.onPick(colour);
  }

  let dragging = false;
  const fromPointer = (event: PointerEvent) => {
    const box = disc.getBoundingClientRect();
    const [hue, s] = at(((event.clientX - box.left) / box.width) * side, ((event.clientY - box.top) / box.height) * side);
    pick([hue, s, point[2]], "s");
  };
  disc.addEventListener("pointerdown", (event) => {
    dragging = true;
    disc.setPointerCapture(event.pointerId);
    fromPointer(event);
    event.preventDefault();
  });
  disc.addEventListener("pointermove", (event) => { if (dragging) fromPointer(event); });
  const stop = () => { dragging = false; };
  disc.addEventListener("pointerup", stop);
  disc.addEventListener("pointercancel", stop);
  disc.addEventListener("keydown", (event) => {
    const step = event.shiftKey ? 15 : 5;
    const [hue, s, v] = point;
    const moves: Record<string, Hsv> = {
      ArrowLeft: [(hue - step + 360) % 360, s, v],
      ArrowRight: [(hue + step) % 360, s, v],
      ArrowUp: [hue, Math.min(1, s + step / 100), v],
      ArrowDown: [hue, Math.max(0, s - step / 100), v],
    };
    const next = moves[event.key];
    if (!next) return;
    event.preventDefault();
    pick(next, "s");
  });

  sync();
  return {
    element,
    show(colour: number, nextLabel: string) {
      // The wheel's own pick coming back through the store: nothing new to show, and
      // re-describing it would wipe what the pick just said.
      if (colour === shown && nextLabel === label) return;
      label = nextLabel;
      if (colour !== shown) {
        shown = colour;
        point = toHsv(colour);
      }
      sync();
    },
  };
}
