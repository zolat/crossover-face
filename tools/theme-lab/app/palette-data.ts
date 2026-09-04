export type PaletteKey = "activity" | "arcade" | "pulse" | "beacon";
export type Mode = "awake" | "always-on" | "temperature";

export type PaletteDefinition = {
  name: string;
  status: "Shipping" | "Mockup only";
  description: string;
  colors: [string, string, string, string];
  ramp: [number, number, number];
};

export const RING_NAMES = ["Outer", "Ring 2", "Ring 3", "Inner"];

export const PALETTES: Record<PaletteKey, PaletteDefinition> = {
  activity: {
    name: "Activity",
    status: "Shipping",
    description: "Watch accents, with gold kept on the smallest ring.",
    colors: ["#FE4646", "#6DC54F", "#1F8FFE", "#E59A0A"],
    ramp: [2, 3, 0],
  },
  arcade: {
    name: "Arcade",
    status: "Mockup only",
    description: "Electric and playful, anchored by moss and warm gold.",
    colors: ["#F45BD8", "#B8D64B", "#1F8FFE", "#FF9900"],
    ramp: [2, 3, 0],
  },
  pulse: {
    name: "Pulse",
    status: "Shipping",
    description: "Production red and teal with an orchid turn.",
    colors: ["#FE4646", "#2FD9C5", "#E879F9", "#B8D64B"],
    ramp: [1, 3, 0],
  },
  beacon: {
    name: "Beacon",
    status: "Shipping",
    description: "Production cyan and indigo, punctuated by red and gold.",
    colors: ["#5CD9F0", "#FE4646", "#8E7BFF", "#E59A0A"],
    ramp: [0, 3, 1],
  },
};

export const PALETTE_KEYS: PaletteKey[] = ["activity", "beacon", "pulse", "arcade"];
export const CANDIDATE_KEYS: PaletteKey[] = ["arcade"];
