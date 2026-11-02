// The face's settings, themes and palette factors, generated from the watch's own
// resources by tools/face_schema_export.py. Nothing here is written by hand.
import raw from "../generated/face-schema.json";

export interface SettingOption {
  value: number;
  label: string;
  labelDrawn: string;
}

export interface Setting {
  key: string;
  type: "list" | "numeric" | "alphaNumeric";
  title: string;
  titleDrawn: string;
  prompt: string;
  promptDrawn: string;
  options?: SettingOption[];
  min?: number;
  max?: number;
  maxLength?: number;
}

export interface Theme {
  id: number;
  name: string;
  colours: [number, number, number, number];
  ramp: [number, number, number];
}

export interface PaletteFactors {
  WEAK_ACTIVE: number;
  WEAK_ALWAYS_ON: number;
  WEAK_HELD_BACK: number;
  WEAK_UNKNOWN: number;
  LIFT: number;
  MARKER: number;
  MARKER_TINT: number;
  SOFT_MARK_TINT: number;
  OVER_TINT: number;
  SUN_TINT: number;
  SUN_HUES: number[];
  BACKING_WHITE: number;
  BACKING_DARK: number;
  RAMP_STEPS: number;
}

export interface FaceSchema {
  settings: Setting[];
  defaults: Record<string, number | string>;
  defaultsDrawn: Record<string, number | string>;
  themes: Theme[];
  themeCustom: number;
  palette: PaletteFactors;
  sources: {
    kinds: Record<string, number>;
    blocks: number[];
    temperatureRange: number[];
    blocksTopRing: number;
    /** HourBands.WINDOW_FLOOR: the narrowest partial window per ring, in hour wedges. */
    blockWindowFloor: number[];
  };
  /** The ring a watch with drawn hands tells the time on, and how it draws it. */
  timeRing: {
    ring: number;
    /** HandStyle.TIME_RING, for each kind of hands. */
    drawn: boolean;
    physical: boolean;
    /** In picker order. */
    styles: { value: number; label: string }[];
    default: number;
    split: number;
    colours: { lit: number; unlit: number };
    /** Palette.TIME_SPLIT_*: how the overlap's hour and minute split from the ring's colour. */
    splitDegrees: number;
    splitChroma: number;
  };
}

export const schema = raw as unknown as FaceSchema;

export function setting(key: string): Setting {
  const found = schema.settings.find((entry) => entry.key === key);
  if (!found) throw new Error(`no setting ${key}`);
  return found;
}

export const SOURCE = schema.sources.kinds;
export const isBlockSource = (source: number) => schema.sources.blocks.includes(source);
export const isTemperatureRange = (source: number) => schema.sources.temperatureRange.includes(source);
