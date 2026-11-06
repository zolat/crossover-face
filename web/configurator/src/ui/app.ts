// The page: the face on the left, drawn by the watch's own rules; what it shows on the
// right; and the code that carries it to the watch along the bottom.
import { type Config, encode, THEME_CUSTOM, tryDecode } from "../codec/configCode";
import { type Device, type Lattice, loadLattice } from "../face/lattice";
import { alwaysOnWorst, BUDGET, relativeLuminance } from "../face/luminance";
import { boostedTheme, build, hex, themeColours } from "../face/palette";
import { randomTheme } from "../face/randomTheme";
import { type Mode, render } from "../face/render";
import { effectiveRings, tellsTime } from "../face/rings";
import { schema, setting } from "../face/schema";
import { themeWarnings } from "../face/warnings";
import { createLibrary, localBacking } from "../library";
import { hideDullPref, remembered, type State, type Store, writeHash } from "../state";
import { choices, select } from "./controls";
import { h, uid } from "./dom";
import { savedSection, suggestedName } from "./library";
import { compactFace } from "./compact";
import { colourWheel, type Wheel } from "./wheel";
import { CARD_MM, calibration, estimatedPxPerMm, faceSize, type View } from "./size";

const DEVICE_NAMES: Record<string, string> = {
  instinctcrossoveramoled: "Instinct Crossover AMOLED",
  epix2pro42mm: "Epix Pro 42 mm",
  epix2: "Epix (Gen 2)",
  epix2pro47mm: "Epix Pro 47 mm",
  epix2pro51mm: "Epix Pro 51 mm",
};

const RING_KEYS = ["ring1", "ring2", "ring3", "ring4", "ring5"] as const;
/** The rings a watch has, by name: the last is the inner one, the 51mm's centre ball. */
const ringNames = (count: number) =>
  count === 5 ? ["Outer ring", "Ring 2", "Ring 3", "Ring 4", "Centre ring"] : ["Outer ring", "Ring 2", "Ring 3", "Inner ring"];
const TEMP_HOURS = schema.sources.kinds.SOURCE_TEMP_HOURS;

export function mountApp(root: HTMLElement, store: Store, devices: Device[]) {
  const canvas = h("canvas", { class: "face", role: "img" });
  // The face at the watch's own resolution; `canvas` shows it copied up by a whole number.
  const source = document.createElement("canvas");
  let drawn = false;
  const card = h("div", { class: "card", "aria-hidden": "true" });
  const faceBox = h("div", { class: "face-box" }, canvas, card);
  const meterText = h("span", {});
  const meterFill = h("i", {});
  const modeSlot = h("div", { class: "mode" });
  const sizeSlot = h("div", { class: "size" });
  const meter = h("div", { class: "meter" }, meterText, h("span", { class: "bar", "aria-hidden": "true" }, meterFill, h("b", {})),
    h("span", {}, "10%"));
  const stage = h("section", { class: "stage", "aria-label": "Preview" }, faceBox, modeSlot, sizeSlot, meter);
  const panel = h("section", { class: "panel" });
  const codeBar = h("footer", { class: "code" });
  root.replaceChildren(h("div", { class: "app" }, stage, panel), codeBar);

  const library = createLibrary(localBacking);
  const saved = savedSection(library, store, (id) => DEVICE_NAMES[id] ?? id);

  let lattice: Lattice | null = null;
  let latticeKey = "";
  const deviceOf = (state: State) => devices.find((device) => device.id === state.device) ?? devices[0];

  // --- the preview ---------------------------------------------------------

  async function drawPreview(state: State) {
    const device = deviceOf(state);
    if (!lattice || latticeKey !== device.lattice) {
      lattice = await loadLattice(device.lattice);
      latticeKey = device.lattice;
    }
    if (store.get() !== state) return; // a newer state is already on its way
    // Always-on draws from the boosted theme, as Palette.build() builds its always-on
    // tables; with the boost off that is the theme itself.
    const theme = themeColours(state.config.theme, custom(state.config));
    const asleep = build(boostedTheme(theme, state.config.alwaysOnBoost));
    const palette = state.mode === "alwaysOn" ? asleep : build(theme);
    source.width = source.height = lattice.screen;
    const context = source.getContext("2d")!;
    const image = context.createImageData(lattice.screen, lattice.screen);
    render(image, lattice, palette, state.config, state.mode, new Date().getDate(), device.drawnHands);
    context.putImageData(image, 0, 0);
    drawn = true;
    fitFace(state);
    canvas.setAttribute("aria-label",
      `${DEVICE_NAMES[device.id] ?? device.id} face, ${state.mode === "alwaysOn" ? "always-on" : "awake"}`);

    const timeStyle = tellsTime(device.drawnHands)
      ? effectiveRings(state.config, device.drawnHands)[schema.timeRing.ring]
      : undefined;
    const worst = alwaysOnWorst(lattice, asleep, timeStyle).total;
    meterText.textContent = `Always-on, brightest case ${(worst * 100).toFixed(1)}%`;
    meterFill.style.width = `${Math.min(100, (worst / BUDGET) * 100)}%`;
  }

  // --- the size ------------------------------------------------------------

  let pxPerMm = calibration.load() ?? estimatedPxPerMm(window.devicePixelRatio);
  let calibrated = calibration.load() !== null;
  let calibrating = false;

  function fitFace(state: State) {
    const device = deviceOf(state);
    const showCard = state.view === "actual" && calibrating;
    canvas.hidden = showCard;
    card.hidden = !showCard;
    if (showCard) {
      card.style.width = `${CARD_MM.width * pxPerMm}px`;
      card.style.height = `${CARD_MM.height * pxPerMm}px`;
      card.style.borderRadius = `${3.18 * pxPerMm}px`;
      return;
    }
    const size = faceSize(state.view, faceBox.clientWidth, window.devicePixelRatio, device.screen, device.displayMm, pxPerMm);
    canvas.style.width = `${size.css}px`;
    canvas.classList.toggle("smooth", size.smooth);
    if (!drawn || source.width !== device.screen) return;
    const side = device.screen * size.backing;
    if (canvas.width !== side) canvas.width = canvas.height = side;
    const context = canvas.getContext("2d")!;
    context.imageSmoothingEnabled = false;
    context.drawImage(source, 0, 0, side, side);
  }

  function drawSize(state: State) {
    shrinking.refresh();
    if (state.view !== "actual") {
      sizeSlot.replaceChildren();
      return;
    }
    if (!calibrating) {
      sizeSlot.replaceChildren(h("p", {},
        calibrated ? "Real size, set with a card. " : "Real size is estimated for this screen. ",
        h("button", { class: "quiet", type: "button", onclick: () => { calibrating = true; drawSize(store.get()); fitFace(store.get()); } },
          calibrated ? "Check it again" : "Set it with a bank card")));
      return;
    }
    const slider = h("input", { id: "calibrate", type: "range", min: "2", max: "9", step: "0.01", value: String(pxPerMm),
      oninput: (event: Event) => { pxPerMm = Number((event.target as HTMLInputElement).value); fitFace(store.get()); } });
    sizeSlot.replaceChildren(
      h("label", { for: "calibrate" }, "Hold any bank card flat against the screen and drag until it fills the outline exactly."),
      slider,
      h("button", { class: "primary", type: "button", onclick: () => {
        calibrating = false;
        calibrated = true;
        calibration.save(pxPerMm);
        drawSize(store.get());
        fitFace(store.get());
      } }, "Done"));
  }

  new ResizeObserver(() => fitFace(store.get())).observe(faceBox);
  // On a phone the face shrinks into a strip at the top rather than scrolling away.
  const shrinking = compactFace(stage, faceBox, canvas, [modeSlot, sizeSlot, meter], () => !calibrating);

  // --- the code ------------------------------------------------------------

  let pasting = false;
  let saving = false;
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

    const themeName = schema.themes.find((theme) => theme.id === state.config.theme)?.name ?? "My colours";
    const nameInput = h("input", { id: "save-name", type: "text", autocomplete: "off", maxlength: 60,
      value: suggestedName(themeName) });
    const saveForm = h("form", {
      class: "paste",
      onsubmit: (event: Event) => {
        event.preventDefault();
        const entry = library.add(nameInput.value, code, state.device);
        saving = false;
        copied = `Saved as ${entry.name}`;
        drawCode(store.get());
        saved.draw(store.get());
        window.setTimeout(() => { copied = ""; drawCode(store.get()); }, 2500);
      },
    }, h("label", { for: "save-name" }, "Name"), nameInput, h("button", { type: "submit" }, "Save"));

    codeBar.replaceChildren(
      h("p", {}, "Your code"),
      h("output", { "aria-label": "Config code" }, code),
      h("div", { class: "actions" },
        h("button", { class: "primary", type: "button", onclick: () => copy(code, "Code") }, "Copy code"),
        h("button", { class: "quiet", type: "button", onclick: () => copy(location.href, "Link") }, "Copy link"),
        h("button", { class: "quiet", type: "button", "aria-expanded": String(saving), "data-key": "save",
          onclick: () => { saving = !saving; pasting = false; drawCode(store.get());
            if (saving) { const input = document.getElementById("save-name") as HTMLInputElement | null; input?.focus(); input?.select(); } } },
          saving ? "Close" : "Save"),
        h("button", { class: "quiet", type: "button", "aria-expanded": String(pasting),
          onclick: () => { pasting = !pasting; saving = false; pasteError = ""; drawCode(store.get());
            if (pasting) (document.getElementById("paste") as HTMLInputElement | null)?.focus(); } },
          pasting ? "Close" : "Load a code"),
        status),
    );
    if (pasting) codeBar.append(pasteForm);
    if (saving) codeBar.append(saveForm);
  }

  // --- the settings --------------------------------------------------------

  const warningsSlot = h("div", { class: "warnings", "aria-live": "polite" });
  /** Which ring the colour wheel is editing, kept across rebuilds of the panel. */
  let editing = 0;
  let wheel: Wheel | null = null;

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
    // What each ring shows on this watch, which is not always what is stored: see rings.ts.
    const ringCount = device.rings;
    const names = ringNames(ringCount);
    const rings = effectiveRings(config, drawn, ringCount);
    const timed = tellsTime(drawn);
    // ring5 is not in settings.xml (Garmin Connect never offers it), so the 51mm's centre
    // ring offers what ring 4 does: Source.offeredFor() keeps blocks off both.
    const ringOptions = (ring: number) =>
      timed && ring === schema.timeRing.ring ? schema.timeRing.styles : options(RING_KEYS[Math.min(ring, 3)]);

    const themeOptions = [
      ...schema.themes.map((theme) => ({ value: theme.id, label: theme.name, swatch: theme.colours })),
      { value: THEME_CUSTOM, label: "Make your own", swatch: config.customColours },
    ];

    const sections: (Node | null)[] = [
      h("h1", {}, "Cross Matrix"),
      h("p", { class: "lede" }, "Set up your face here, then paste the code into Garmin Connect."),
      choices("Watch", devices.map((entry) => ({ value: entry.id, label: DEVICE_NAMES[entry.id] ?? entry.id })),
        state.device, (value) => store.set({ device: String(value) })),
      choices("Colours", themeOptions, config.theme, (value) => set({ theme: Number(value) })),
      h("button", { class: "quiet randomise", type: "button", "data-key": "randomise", onclick: () => {
        const theme = randomTheme();
        set({ theme: THEME_CUSTOM, customColours: theme.colours, customRamp: theme.ramp });
      } }, "Randomise colours"),
      config.theme === THEME_CUSTOM ? builder(config, ringCount) : null,
      h("h2", {}, "Rings, outside in"),
      h("div", { class: "rings" }, ...RING_KEYS.slice(0, ringCount).map((key, ring) =>
        select(names[ring], ringOptions(ring), rings[ring], (value) => set({ [key]: value }),
          h("span", { class: "sw", style: `background:var(--r${ring + 1})`, "aria-hidden": "true" })))),
      timed ? h("p", { class: "note" }, "This watch tells the time in its outer ring. The preview shows ten past ten.") : null,
      // The time ring's extras: only a watch that has one draws them, as only it has the rows.
      ...(timed ? schema.timeRing.extras.map((extra) =>
        choices(extra.title, extra.options, config[extra.key], (value) => set({ [extra.key]: Number(value) }),
          extra.key === "timeSeconds" ? "Awake only: always-on updates once a minute." : undefined)) : []),
      rings.some((source) => source === TEMP_HOURS) ? tempAhead(config) : null,
      h("h2", {}, "Details"),
      // Only where there are hands to back; a watch with none ignores the setting.
      drawn ? null : choices(label("handBacking"), options("handBacking"), config.handBacking, (value) => set({ handBacking: Number(value) })),
      choices(label("alwaysOnFill"), options("alwaysOnFill"), config.alwaysOnFill, (value) => set({ alwaysOnFill: Number(value) })),
      choices(label("alwaysOnBoost"), options("alwaysOnBoost"), config.alwaysOnBoost,
        (value) => set({ alwaysOnBoost: Number(value) }),
        "The watch dims its screen in always-on. This draws always-on in lighter colours to make up for it."),
      choices(label("dotRotation"), options("dotRotation"), config.dotRotation, (value) => set({ dotRotation: Number(value) })),
      choices(label("showDate"), options("showDate"), config.showDate, (value) => set({ showDate: Number(value) })),
      config.showDate === 1
        ? choices(label("dateOutline"), options("dateOutline"), config.dateOutline, (value) => set({ dateOutline: Number(value) }))
        : null,
      h("p", { class: "note" }, drawn
        ? "The preview shows typical readings. Every ring fills clockwise from twelve."
        : "The preview shows typical readings, under where the watch's own hands sit. Every ring fills clockwise from twelve."),
    ];
    panel.replaceChildren(...sections.filter((node): node is Node => node !== null), saved.element);
    saved.draw(state);
    drawWarnings(state);
  }

  /**
   * The custom theme's colours, one per ring this watch has. The code carries all five
   * whichever watch is chosen; a four-ring watch just never draws the fifth.
   */
  function builder(config: Config, ringCount: number): HTMLElement {
    const names = ringNames(ringCount);
    editing = Math.min(editing, ringCount - 1);
    const tabsName = uid("editing");
    const tabs = names.map((name, ring) => {
      const id = `colour-${ring}`;
      return h("span", { class: "ring-tab" },
        h("input", {
          type: "radio", name: tabsName, id, value: String(ring), checked: ring === editing, "data-key": id,
          onchange: () => {
            editing = ring;
            wheel?.show(store.get().config.customColours[ring], names[ring]);
          },
        }),
        h("label", { for: id }, h("i", { style: `background:var(--r${ring + 1})`, "aria-hidden": "true" }), name));
    });
    wheel = colourWheel({
      colour: config.customColours[editing],
      label: names[editing],
      hideDull: hideDullPref.load(),
      onHideDull: (hide) => hideDullPref.save(hide),
      onPick: (colour) => {
        const next = [...store.get().config.customColours] as Config["customColours"];
        next[editing] = colour;
        store.setConfig({ customColours: next });
      },
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
        }, ...stopChoices(names, stop).map(([name, ring]) =>
          h("option", { value: String(ring), selected: ring === stop }, `${name} colour`))));
    });
    return h("fieldset", { class: "builder" }, h("legend", {}, "Your colours"),
      h("div", { class: "ring-tabs", role: "radiogroup", "aria-label": "Ring to colour" }, ...tabs),
      wheel.element,
      h("p", { class: "hint" }, "Temperature runs through three of them, cold to hot."),
      h("div", { class: "stops" }, ...stops),
      warningsSlot);
  }

  /** A stop may name any colour this watch draws, and keeps one it already names. */
  function stopChoices(names: string[], stop: number): [string, number][] {
    const out = names.map((name, ring): [string, number] => [name, ring]);
    if (stop >= names.length) out.push(["Centre ring", stop]);
    return out;
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
    modeSlot.replaceChildren(
      choices("Show", [{ value: "awake", label: "Awake" }, { value: "alwaysOn", label: "Always-on" }],
        state.mode, (value) => store.set({ mode: value as Mode })),
      choices("Size", [{ value: "fit", label: "Large" }, { value: "actual", label: "Real size" }],
        state.view, (value) => { calibrating = false; store.set({ view: value as View }); }));
    drawSize(state);
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
      previous.view === state.view &&
      encode({ ...previous.config, customColours: state.config.customColours }) === code;
    if (onlyColours) {
      // The wheel is being dragged: rebuilding it would drop it from under the pointer.
      wheel?.show(state.config.customColours[editing], ringNames(deviceOf(state).rings)[editing]);
      drawWarnings(state);
      return;
    }
    if (previous === null || previous.mode !== state.mode || previous.view !== state.view) drawMode(state);
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
