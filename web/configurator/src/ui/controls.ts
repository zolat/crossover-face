// The two controls the page is built from: a set of mutually exclusive choices shown as
// pills (a real radio group underneath, so arrows and screen readers work), and a select.
import { h, uid } from "./dom";

export interface Choice {
  value: number | string;
  label: string;
  swatch?: number[];
}

export function choices(legend: string, options: Choice[], current: number | string,
                        onPick: (value: number | string) => void, hint?: string): HTMLFieldSetElement {
  const name = uid("choice");
  const group = h("div", { class: "pills" });
  for (const option of options) {
    const id = uid("opt");
    const input = h("input", {
      type: "radio", name, id, value: String(option.value), checked: option.value === current,
      onchange: () => onPick(option.value),
    });
    const swatch = option.swatch
      ? h("span", { class: "dots", "aria-hidden": "true" },
          ...option.swatch.map((colour) => h("i", { style: `background:#${colour.toString(16).padStart(6, "0")}` })))
      : null;
    group.append(h("span", { class: "pill" }, input, h("label", { for: id }, swatch, option.label)));
  }
  return h("fieldset", { class: "field" }, h("legend", {}, legend), hint ? h("p", { class: "hint" }, hint) : null, group);
}

export function select(label: string, options: Choice[], current: number, onPick: (value: number) => void,
                       lead?: Node): HTMLDivElement {
  const id = uid("sel");
  const control = h("select", { id, onchange: (event: Event) => onPick(Number((event.target as HTMLSelectElement).value)) },
    ...options.map((option) => h("option", { value: String(option.value), selected: option.value === current }, option.label)));
  return h("div", { class: "ring" }, lead ?? null, control, h("label", { for: id }, label));
}
