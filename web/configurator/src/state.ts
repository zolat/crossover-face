// The page's state: which watch, which configuration, and how the preview shows it.
// The configuration is exactly what a config code carries; the watch is not in the code,
// because the face itself already knows which watch it is on.
import { type Config, DEFAULT_CONFIG, tryDecode } from "./codec/configCode";
import type { Mode } from "./face/render";
import { tellsTime } from "./face/rings";
import { schema } from "./face/schema";
import type { View } from "./ui/size";

export interface State {
  device: string;
  config: Config;
  mode: Mode;
  view: View;
}

type Listener = (state: State, previous: State) => void;

export function createStore(initial: State) {
  let state = initial;
  const listeners: Listener[] = [];
  return {
    get: () => state,
    set(patch: Partial<State>) {
      const previous = state;
      state = { ...state, ...patch };
      listeners.forEach((listener) => listener(state, previous));
    },
    setConfig(patch: Partial<Config>) {
      this.set({ config: { ...state.config, ...patch } });
    },
    subscribe(listener: Listener) {
      listeners.push(listener);
    },
  };
}

export type Store = ReturnType<typeof createStore>;

export const DEFAULT_DEVICE = "instinctcrossoveramoled";

/** `#c=<code>&w=<device>`: a link that opens the page on a configuration. */
export function readHash(hash: string): { config?: Config; device?: string; error?: string } {
  const params = new URLSearchParams(hash.replace(/^#/, ""));
  const out: { config?: Config; device?: string; error?: string } = {};
  const code = params.get("c");
  if (code) {
    const decoded = tryDecode(code);
    if (decoded.ok) out.config = decoded.config;
    else out.error = decoded.reason;
  }
  const device = params.get("w");
  if (device) out.device = device;
  return out;
}

export function writeHash(code: string, device: string): string {
  return `#c=${code}&w=${device}`;
}

export function initialConfig(drawnHands: boolean, drawnDefaults: Record<string, number | string>): Config {
  const config = structuredClone(DEFAULT_CONFIG);
  // A fresh watch draws ring 2 as Off: properties.xml seeds it with the retired source.
  // That is the watch's quirk to keep, not a first impression to give, so the page
  // starts it on StatMap's own fallback for that ring.
  config.ring2 = 6;
  if (drawnHands && typeof drawnDefaults.handBacking === "number") config.handBacking = drawnDefaults.handBacking;
  // The time ring's style is what such a watch loads and publishes as ring1, so the
  // first code matches the watch's own.
  if (tellsTime(drawnHands)) config[(["ring1", "ring2", "ring3", "ring4"] as const)[schema.timeRing.ring]] = schema.timeRing.default;
  return config;
}

/** Per-viewer convenience only: the page works the same without it. */
export const remembered = {
  load(): { device?: string; code?: string } {
    try {
      return JSON.parse(localStorage.getItem("crossover-face") ?? "{}");
    } catch {
      return {};
    }
  },
  save(device: string, code: string) {
    try {
      localStorage.setItem("crossover-face", JSON.stringify({ device, code }));
    } catch {
      // Private mode or blocked storage: nothing to remember, nothing lost.
    }
  },
};
