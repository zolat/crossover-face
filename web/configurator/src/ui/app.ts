// The page: the face on the left, drawn by the watch's own rules; what it shows on the
// right; and the code that carries it to the watch along the bottom.
import { type Config, encode, THEME_CUSTOM, tryDecode } from "../codec/configCode";
import { type Device, type Lattice, loadLattice } from "../face/lattice";
import { alwaysOnWorst, BUDGET, relativeLuminance } from "../face/luminance";
import { build, fromHex, hex, themeColours } from "../face/palette";
import { type Mode, render } from "../face/render";
import { schema, setting } from "../face/schema";
import { themeWarnings } from "../face/warnings";
import { remembered, type State, type Store, writeHash } from "../state";
import { choices, select } from "./controls";
import { h } from "./dom";

const DEVICE_NAMES: Record<string, string> = {
  instinctcrossoveramoled: "Instinct Crossover AMOLED",
  epix2pro42mm: "Epix Pro 42 mm",
  epix2: "Epix (Gen 2)",
  epix2pro47mm: "Epix Pro 47 mm",
  epix2pro51mm: "Epix Pro 51 mm",
};

const RING_KEYS = ["ring1", "ring2", "ring3", "ring4"] as const;
const RING_NAMES = ["Outer ring", "Ring 2", "Ring 3", "Inner ring"];
const TEMP_HOURS = schema.sources.kinds.SOURCE_TEMP_HOURS;

export function mountApp(root: HTMLElement, store: Store, devices: Device[]) {
  const canvas = h("canvas", { class: "face", role: "img" });
  const meterText = h("span", {});
  const meterFill = h("i", {});
  const modeSlot = h("div", { class: "mode" });
  const stage = h("section", { class: "stage", "aria-label": "Preview" }, canvas, modeSlot,
    h("div", { class: "meter" }, meterText, h("span", { class: "bar", "aria-hidden": "true" }, meterFill, h("b", {})),
      h("span", {}, "10%")));
  const panel = h("section", { class: "panel" });
  const codeBar = h("footer", { class: "code" });
  root.replaceChildren(h("div", { class: "app" }, stage, panel), codeBar);

  let lattice: Lattice | null = null;
  let latticeScreen = 0;
  const deviceOf = (state: State) => devices.find((device) => device.id === state.device) ?? devices[0];

  // --- the preview ---------------------------------------------------------

  async function drawPreview(state: State) {
    const device = deviceOf(state);
    if (!lattice || latticeScreen !== device.screen) {
      lattice = await loadLattice(device.screen);
      latticeScreen = device.screen;
    }
    if (store.get() !== state) return; // a newer state is already on its way
    const palette = build(themeColours(state.config.theme, custom(state.config)));
    canvas.width = canvas.height = lattice.screen;
    const context = canvas.getContext("2d")!;
    const image = context.createImageData(lattice.screen, lattice.screen);
    render(image, lattice, palette, state.config, state.mode);
    context.putImageData(image, 0, 0);
    canvas.setAttribute("aria-label",
      `${DEVICE_NAMES[device.id] ?? device.id} face, ${state.mode === "alwaysOn" ? "always-on" : "awake"}`);

    const worst = alwaysOnWorst(lattice, palette).total;
    meterText.textContent = `Always-on, brightest case ${(worst * 100).toFixed(1)}%`;
    meterFill.style.width = `${Math.min(100, (worst / BUDGET) * 100)}%`;
  }

  // --- the code ------------------------------------------------------------

  let pasting = false;
  let pasteError = "";
  let copied = "";

  function drawCode(state: State) {
    const code = encode(state.config);
    const status = h("span", { class: "status", role: "status" }, copied);
    const copy = async (text: string, what: string) => {
      try {
        await navigator.clipboard.writeText(text);
        copied = `${what} copied`;
      } catch {
        copied = "Copying is blocked here: select the code and copy it by hand";
      }
      drawCode(store.get());
      window.setTimeout(() => {
        copied = "";
        drawCode(store.get());
      }, 2500);
    };
    const input = h("input", { id: "paste", type: "text", autocomplete: "off", spellcheck: "false",
      placeholder: "Paste a code from Garmin Connect", "aria-describedby": pasteError ? "paste-error" : undefined });
    const pasteForm = h("form", {
      class: "paste",
      onsubmit: (event: Event) => {
        event.preventDefault();
        const decoded = tryDecode(input.value);
        if (decoded.ok) {
          pasting = false;
          pasteError = "";
          store.set({ config: decoded.config });
        } else {
          pasteError = `That code did not load: ${decoded.reason}. Copy it again, whole, and paste it here.`;
          drawCode(store.get());
          (document.getElementById("paste") as HTMLInputElement | null)?.focus();
        }
      },
    }, h("label", { for: "paste" }, "Code to load"), input, h("button", { type: "submit" }, "Load code"),
      pasteError ? h("p", { id: "paste-error", class: "error" }, pasteError) : null);

    codeBar.replaceChildren(
      h("p", {}, "Your code"),
      h("output", { "aria-label": "Config code" }, code),
      h("div", { class: "actions" },
        h("button", { class: "primary", type: "button", onclick: () => copy(code, "Code") }, "Copy code"),
        h("button", { class: "quiet", type: "button", onclick: () => copy(location.href, "Link") }, "Copy link"),
        h("button", { class: "quiet", type: "button", "aria-expanded": String(pasting),
          onclick: () => { pasting = !pasting; pasteError = ""; drawCode(store.get());
            if (pasting) (document.getElementById("paste") as HTMLInputElement | null)?.focus(); } },
          pasting ? "Close" : "Load a code"),
        status),
    );
    if (pasting) codeBar.append(pasteForm);
  }

  // --- the settings --------------------------------------------------------

  const warningsSlot = h("div", { class: "warnings", "aria-live": "polite" });

  function drawWarnings(state: State) {
    if (state.config.theme !== THEME_CUSTOM) {
      warningsSlot.replaceChildren();
      return;
    }
    const found = themeWarnings(build(custom(state.config)));
    warningsSlot.replaceChildren(...found.map((text) => h("p", {}, text)));
  }

  function drawPanel(state: State) {
    const device = deviceOf(state);
    const drawn = device.drawnHands;
    const config = state.config;
    const label = (key: string) => (drawn ? setting(key).titleDrawn : setting(key).title);
    const options = (key: string) =>
      (setting(key).options ?? []).map((option) => ({ value: option.value, label: drawn ? option.labelDrawn : option.label }));
    const set = (patch: Partial<Config>) => store.setConfig(patch);

    const themeOptions = [
      ...schema.themes.map((theme) => ({ value: theme.id, label: theme.name, swatch: theme.colours })),
      { value: THEME_CUSTOM, label: "Make your own", swatch: config.customColours },
    ];

    const sections: (Node | null)[] = [
      h("h1", {}, "Crossover Face"),
      h("p", { class: "lede" }, "Set up your face here, then paste the code into Garmin Connect."),
      choices("Watch", devices.map((entry) => ({ value: entry.id, label: DEVICE_NAMES[entry.id] ?? entry.id })),
        state.device, (value) => store.set({ device: String(value) })),
      choices("Colours", themeOptions, config.theme, (value) => set({ theme: Number(value) })),
      config.theme === THEME_CUSTOM ? builder(config) : null,
      h("h2", {}, "Rings, outside in"),
      h("div", { class: "rings" }, ...RING_KEYS.map((key, ring) =>
        select(RING_NAMES[ring], options(key), config[key], (value) => set({ [key]: value }),
          h("span", { class: "sw", style: `background:var(--r${ring + 1})`, "aria-hidden": "true" })))),
      RING_KEYS.some((key) => config[key] === TEMP_HOURS) ? tempAhead(config) : null,
      h("h2", {}, "Details"),
      choices(label("handBacking"), options("handBacking"), config.handBacking, (value) => set({ handBacking: Number(value) })),
      choices(label("alwaysOnFill"), options("alwaysOnFill"), config.alwaysOnFill, (value) => set({ alwaysOnFill: Number(value) })),
      choices(label("dotRotation"), options("dotRotation"), config.dotRotation, (value) => set({ dotRotation: Number(value) })),
      choices(label("showDate"), options("showDate"), config.showDate, (value) => set({ showDate: Number(value) })),
      config.showDate === 1
        ? choices(label("dateOutline"), options("dateOutline"), config.dateOutline, (value) => set({ dateOutline: Number(value) }))
        : null,
      h("p", { class: "note" }, "The preview shows typical readings. Hands and the date are drawn by the watch itself."),
    ];
    panel.replaceChildren(...sections.filter((node): node is Node => node !== null));
    drawWarnings(state);
  }

  function builder(config: Config): HTMLElement {
    const rows = config.customColours.map((colour, ring) => {
      const id = `colour-${ring}`;
      const picker = h("input", {
        id, type: "color", value: hex(colour), "data-key": id,
        oninput: (event: Event) => {
          const next = [...store.get().config.customColours] as Config["customColours"];
          next[ring] = fromHex((event.target as HTMLInputElement).value);
          store.setConfig({ customColours: next });
        },
      });
      return h("div", { class: "colour" }, picker, h("label", { for: id }, RING_NAMES[ring]));
    });
    const stopNames = ["Cold", "Middle", "Hot"];
    const stops = config.customRamp.map((stop, point) => {
      const id = `stop-${point}`;
      return h("div", { class: "stop" }, h("label", { for: id }, stopNames[point]),
        h("select", {
          id, "data-key": id,
          onchange: (event: Event) => {
            const next = [...store.get().config.customRamp] as Config["customRamp"];
            next[point] = Number((event.target as HTMLSelectElement).value);
            store.setConfig({ customRamp: next });
          },
        }, ...RING_NAMES.map((name, ring) => h("option", { value: String(ring), selected: ring === stop }, `${name} colour`))));
    });
    return h("fieldset", { class: "builder" }, h("legend", {}, "Your colours"),
      h("div", { class: "colours" }, ...rows),
      h("p", { class: "hint" }, "Temperature runs through three of them, cold to hot."),
      h("div", { class: "stops" }, ...stops),
      warningsSlot);
  }

  function tempAhead(config: Config): HTMLElement {
    const low = setting("tempAheadLow");
    const field = (key: "tempAheadLow" | "tempAheadHigh", text: string) => {
      const id = `temp-${key}`;
      return h("div", { class: "temp" }, h("label", { for: id }, text),
        h("input", { id, type: "number", inputmode: "numeric", min: low.min, max: low.max, step: 1, value: config[key],
          "data-key": id,
          onchange: (event: Event) => {
            const value = Math.round(Number((event.target as HTMLInputElement).value));
            if (Number.isFinite(value)) store.setConfig({ [key]: Math.min(low.max!, Math.max(low.min!, value)) });
          } }), h("span", {}, "°C"));
    };
    return h("fieldset", { class: "field" }, h("legend", {}, "Temperature, next 12 hours"),
      h("p", { class: "hint" }, "An hour at the first temperature shows empty, at the second full."),
      h("div", { class: "temps" }, field("tempAheadLow", "Empty at"), field("tempAheadHigh", "Full at")));
  }

  function drawMode(state: State) {
    modeSlot.replaceChildren(choices("Show", [{ value: "awake", label: "Awake" }, { value: "alwaysOn", label: "Always-on" }],
      state.mode, (value) => store.set({ mode: value as Mode })));
  }

  // --- wiring --------------------------------------------------------------

  function paintAccents(state: State) {
    const colours = themeColours(state.config.theme, custom(state.config)).colours;
    colours.forEach((colour, ring) => document.documentElement.style.setProperty(`--r${ring + 1}`, hex(colour)));
    // The code is the one piece of text in a theme colour, so it takes the brightest
    // of the four, and plain text when even that would be hard to read on black.
    const brightest = [...colours].sort((a, b) => relativeLuminance(b) - relativeLuminance(a))[0];
    document.documentElement.style.setProperty("--code", relativeLuminance(brightest) >= 0.35 ? hex(brightest) : "var(--text)");
  }

  function rememberFocus(): { key: string | null; value: string | null } {
    const active = document.activeElement as HTMLElement | null;
    if (!active || !panel.contains(active) && !modeSlot.contains(active)) return { key: null, value: null };
    if (active instanceof HTMLInputElement && active.type === "radio") return { key: `radio:${active.name}`, value: active.value };
    return { key: active.getAttribute("data-key") ?? active.id, value: null };
  }

  function restoreFocus(saved: { key: string | null; value: string | null }, legendText: string | null) {
    if (!saved.key) return;
    if (saved.key.startsWith("radio:") && legendText) {
      // Radio names are regenerated, so find the group by its legend instead.
      for (const fieldset of panel.querySelectorAll("fieldset")) {
        if (fieldset.querySelector("legend")?.textContent === legendText) {
          (fieldset.querySelector(`input[value="${CSS.escape(saved.value ?? "")}"]`) as HTMLElement | null)?.focus();
          return;
        }
      }
      return;
    }
    (panel.querySelector(`[data-key="${CSS.escape(saved.key)}"], #${CSS.escape(saved.key)}`) as HTMLElement | null)?.focus();
  }

  function update(state: State, previous: State | null) {
    const code = encode(state.config);
    history.replaceState(null, "", writeHash(code, state.device));
    remembered.save(state.device, code);
    paintAccents(state);
    void drawPreview(state);
    drawCode(state);
    const onlyColours = previous !== null && previous.device === state.device && previous.mode === state.mode &&
      encode({ ...previous.config, customColours: state.config.customColours }) === code;
    if (onlyColours) {
      // A colour picker is open: rebuilding it would close it under the wearer's cursor.
      drawWarnings(state);
      return;
    }
    if (previous === null || previous.mode !== state.mode) drawMode(state);
    if (previous === null || previous.device !== state.device || previous.config !== state.config) {
      const saved = rememberFocus();
      const legend = (document.activeElement?.closest("fieldset")?.querySelector("legend")?.textContent) ?? null;
      drawPanel(state);
      restoreFocus(saved, legend);
    }
  }

  store.subscribe((state, previous) => update(state, previous));
  update(store.get(), null);
}

function custom(config: Config) {
  return { colours: config.customColours, ramp: config.customRamp };
}
