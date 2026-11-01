// The "Saved" section: configs kept in this browser, loaded with a click, and moved
// between browsers as a file. Loading changes the page only; the watch hears nothing
// until a code is copied to it, as always.
import { encode, tryDecode } from "../codec/configCode";
import type { ImportResult, Library, Saved } from "../library";
import { hex, themeColours } from "../face/palette";
import type { State, Store } from "../state";
import { h } from "./dom";

export const EXPORT_NAME = "crossover-face-configs.json";

export interface SavedSection {
  element: HTMLElement;
  draw(state: State): void;
}

export function savedSection(library: Library, store: Store, deviceName: (id: string) => string): SavedSection {
  const element = h("section", { class: "saved", "aria-labelledby": "saved-title" });
  let renaming: string | null = null;
  let status: Node[] = [];
  let statusTimer = 0;

  const say = (nodes: (Node | string)[], ms = 6000) => {
    status = nodes.map((node) => (typeof node === "string" ? document.createTextNode(node) : node));
    window.clearTimeout(statusTimer);
    statusTimer = window.setTimeout(() => { status = []; draw(store.get()); }, ms);
    draw(store.get());
  };

  function load(entry: Saved) {
    const decoded = tryDecode(entry.code);
    if (!decoded.ok) {
      say([`${entry.name} did not load: ${decoded.reason}.`]);
      return;
    }
    store.set({ config: decoded.config, device: entry.device });
    say([`Showing ${entry.name}. Nothing has been sent to your watch.`], 4000);
  }

  function remove(entry: Saved) {
    const removed = library.remove(entry.id);
    if (!removed) return;
    say([`Deleted ${removed.name}. `, h("button", { class: "quiet", type: "button", "data-key": "undo",
      onclick: () => { library.restore(removed); status = []; draw(store.get()); } }, "Undo")]);
  }

  function exportAll() {
    const url = URL.createObjectURL(new Blob([library.exportFile()], { type: "application/json" }));
    const link = h("a", { href: url, download: EXPORT_NAME });
    document.body.append(link);
    link.click();
    link.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  const fileInput = h("input", { id: "import-file", type: "file", accept: "application/json,.json", hidden: true,
    onchange: async (event: Event) => {
      const input = event.target as HTMLInputElement;
      const file = input.files?.[0];
      input.value = "";
      if (!file) return;
      try {
        const result = library.importFile(await file.text());
        say([importMessage(result)]);
      } catch (error) {
        say([`Nothing imported: ${(error as Error).message}.`]);
      }
    } });

  function row(entry: Saved, current: string): HTMLElement {
    const decoded = tryDecode(entry.code);
    const colours = decoded.ok
      ? themeColours(decoded.config.theme, { colours: decoded.config.customColours, ramp: decoded.config.customRamp }).colours
      : [];
    const showing = entry.code === current && entry.device === store.get().device;
    const dots = h("span", { class: "dots", "aria-hidden": "true" }, ...colours.map((colour) => h("i", { style: `background:${hex(colour)}` })));

    if (renaming === entry.id) {
      const input = h("input", { type: "text", value: entry.name, "aria-label": `New name for ${entry.name}`,
        "data-key": `rename-${entry.id}`, maxlength: 60 });
      const done = (save: boolean) => {
        if (save) library.rename(entry.id, input.value);
        renaming = null;
        draw(store.get());
      };
      input.addEventListener("keydown", (event) => {
        if (event.key === "Enter") { event.preventDefault(); done(true); }
        if (event.key === "Escape") done(false);
      });
      queueMicrotask(() => { input.focus(); input.select(); });
      return h("li", { class: "entry" }, dots,
        h("form", { class: "rename", onsubmit: (event: Event) => { event.preventDefault(); done(true); } },
          input, h("button", { type: "submit" }, "Save name"),
          h("button", { class: "quiet", type: "button", onclick: () => done(false) }, "Cancel")));
    }

    return h("li", { class: showing ? "entry showing" : "entry" }, dots,
      h("span", { class: "what" }, h("span", { class: "name" }, entry.name),
        h("span", { class: "sub" }, showing ? `${deviceName(entry.device)} · showing` : deviceName(entry.device))),
      h("span", { class: "row-actions" },
        h("button", { type: "button", class: "load", "data-key": `load-${entry.id}`, onclick: () => load(entry),
          "aria-label": `Load ${entry.name}` }, "Load"),
        h("button", { type: "button", class: "quiet", "data-key": `rename-btn-${entry.id}`,
          onclick: () => { renaming = entry.id; draw(store.get()); }, "aria-label": `Rename ${entry.name}` }, "Rename"),
        h("button", { type: "button", class: "quiet", "data-key": `delete-${entry.id}`, onclick: () => remove(entry),
          "aria-label": `Delete ${entry.name}` }, "Delete")));
  }

  function draw(state: State) {
    const current = encode(state.config);
    const entries = library.list();
    const parts: (Node | null)[] = [
      h("h2", { id: "saved-title" }, "Saved in this browser"),
      entries.length
        ? h("ul", { class: "entries" }, ...entries.map((entry) => row(entry, current)))
        : h("p", { class: "hint" }, "Save a setup from the bar below to keep it here. Nothing is sent to your watch."),
      library.persistent ? null : h("p", { class: "hint" }, "This browser is blocking storage, so these go when the page closes. Export them to keep them."),
      h("div", { class: "library-actions" },
        h("button", { type: "button", class: "quiet", "data-key": "export", disabled: entries.length === 0, onclick: exportAll }, "Export all"),
        h("button", { type: "button", class: "quiet", "data-key": "import", onclick: () => fileInput.click() }, "Import a file"),
        fileInput),
      h("p", { class: "status", role: "status" }, ...status),
    ];
    element.replaceChildren(...parts.filter((part): part is Node => part !== null));
  }

  return { element, draw };
}

export function importMessage({ added, duplicates, invalid }: ImportResult): string {
  const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;
  const skipped = [
    duplicates ? `${plural(duplicates, "was", "were")} already saved` : "",
    invalid ? `${plural(invalid, "was", "were")} damaged` : "",
  ].filter(Boolean).join(" and ");
  const lead = added ? `Added ${plural(added, "config", "configs")}` : "Nothing new to add";
  return skipped ? `${lead}; ${skipped}.` : `${lead}.`;
}

/** A name to offer when saving: the colours' name and today's date. */
export function suggestedName(themeName: string): string {
  const date = new Date().toLocaleDateString(undefined, { day: "numeric", month: "short" });
  return `${themeName}, ${date}`;
}
