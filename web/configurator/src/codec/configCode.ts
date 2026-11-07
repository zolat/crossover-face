// The config code: the face's whole configuration as one pasteable string.
//
// docs/config-code.md is the specification. This is one of three codecs held to
// tools/testdata/config-codes.json, beside tools/simctl/configcode.py and
// source/settings/ConfigCode.mc.

/** The version this page writes; it reads versions 1 to 3 too, filling what each lacks with the defaults. */
export const VERSION = 4;
export const LENGTH = 36;
/** Bytes per version, the CRC included; the payload is two fewer. */
const LENGTHS: Record<number, number> = { 1: 28, 2: 33, 3: 34, 4: LENGTH };
const TEMP_OFFSET = 20;

export const THEME_CUSTOM = 99;
export const THEME_IDS = [0, 1, 7, 8, 9, 10, 11, THEME_CUSTOM] as const;
export const TEMP_MIN = -20;
export const TEMP_MAX = 50;
/** Source.COUNT - 1. The two time styles, 14 and 15, are the top. */
export const SOURCE_MAX = 15;
/** Always-on brightness: Off, Bright, Brightest. */
export const BOOST_MAX = 2;
/** The time ring's two extras, appended in version 4, each Off (0) or On (1). */
export const EXTRA_FIELDS = [
  ["timeHourMarks", 1],
  ["timeSeconds", 1],
] as const;

export interface Config {
  theme: number;
  handBacking: number;
  alwaysOnFill: number;
  dotRotation: number;
  showDate: number;
  dateOutline: number;
  ring1: number;
  ring2: number;
  ring3: number;
  ring4: number;
  /** The 51mm's centre ball. Every watch carries it; only the 51mm draws it. */
  ring5: number;
  /** Always-on drawn brighter than awake: 0 Off, 1 Bright, 2 Brightest. Version 3. */
  alwaysOnBoost: number;
  /** The time ring's hour marks, on its outer edge. Only a time-ring watch draws them. Version 4. */
  timeHourMarks: number;
  /** The time ring's seconds dot, on its inner edge, awake only. Version 4. */
  timeSeconds: number;
  tempAheadLow: number;
  tempAheadHigh: number;
  /** Five 0xRRGGBB colours, outermost ring first; the fifth is the 51mm's centre ball. */
  customColours: [number, number, number, number, number];
  /** Cold, mid and hot stops: indices into customColours. */
  customRamp: [number, number, number];
}

/** The one-byte settings after the theme, in byte order, with their top value. */
export const ENUM_FIELDS = [
  ["handBacking", 2],
  ["alwaysOnFill", 1],
  ["dotRotation", 1],
  ["showDate", 1],
  ["dateOutline", 2],
  ["ring1", SOURCE_MAX],
  ["ring2", SOURCE_MAX],
  ["ring3", SOURCE_MAX],
  ["ring4", SOURCE_MAX],
] as const satisfies ReadonlyArray<readonly [keyof Config, number]>;

export const DEFAULT_CONFIG: Config = {
  theme: 0,
  handBacking: 0,
  alwaysOnFill: 0,
  dotRotation: 0,
  showDate: 1,
  dateOutline: 1,
  ring1: 0,
  // properties.xml seeds ring2 with the retired source, which loads as Off.
  ring2: 8,
  ring3: 2,
  ring4: 3,
  // StatMap.RING_DEFAULTS[4]: the 51mm's centre ball shows Steps.
  ring5: 0,
  alwaysOnBoost: 0,
  timeHourMarks: 0,
  timeSeconds: 0,
  tempAheadLow: 0,
  tempAheadHigh: 45,
  customColours: [0xe879f9, 0xb8d64b, 0x7fd4ff, 0xff6b5b, 0xe5b33a],
  customRamp: [2, 0, 3],
};

export class ConfigCodeError extends Error {}

/** CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, unreflected, no final XOR. */
export function crc16(bytes: ArrayLike<number>, count = bytes.length): number {
  let crc = 0xffff;
  for (let i = 0; i < count; i++) {
    crc ^= bytes[i] << 8;
    for (let bit = 0; bit < 8; bit++) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc;
}

function isByteInRange(value: unknown, high: number): value is number {
  return Number.isInteger(value) && (value as number) >= 0 && (value as number) <= high;
}

/** Every reason a config cannot be encoded, or an empty list. */
export function problems(config: Config): string[] {
  const out: string[] = [];
  if (!(THEME_IDS as readonly number[]).includes(config.theme)) {
    out.push(`theme ${config.theme} is not one of ${THEME_IDS.join(", ")}`);
  }
  for (const [key, high] of [...ENUM_FIELDS, ["ring5", SOURCE_MAX] as const, ["alwaysOnBoost", BOOST_MAX] as const,
                             ...EXTRA_FIELDS]) {
    if (!isByteInRange(config[key], high)) out.push(`${key} ${config[key]} is outside 0..${high}`);
  }
  for (const key of ["tempAheadLow", "tempAheadHigh"] as const) {
    const value = config[key];
    if (!Number.isInteger(value) || value < TEMP_MIN || value > TEMP_MAX) {
      out.push(`${key} ${value} is outside ${TEMP_MIN}..${TEMP_MAX}`);
    }
  }
  if (config.customColours.length !== 5 || !config.customColours.every((c) => isByteInRange(c, 0xffffff))) {
    out.push("customColours must be five 0xRRGGBB values");
  }
  if (config.customRamp.length !== 3 || !config.customRamp.every((s) => isByteInRange(s, 4))) {
    out.push("customRamp must be three indices 0..4");
  }
  return out;
}

export function toBytes(config: Config): Uint8Array {
  const issues = problems(config);
  if (issues.length) throw new ConfigCodeError(issues.join("; "));
  const bytes = new Uint8Array(LENGTH);
  bytes[0] = VERSION;
  bytes[1] = config.theme;
  ENUM_FIELDS.forEach(([key], i) => {
    bytes[2 + i] = config[key];
  });
  bytes[11] = config.tempAheadLow + TEMP_OFFSET;
  bytes[12] = config.tempAheadHigh + TEMP_OFFSET;
  const putColour = (colour: number, at: number) => {
    bytes[at] = (colour >> 16) & 0xff;
    bytes[at + 1] = (colour >> 8) & 0xff;
    bytes[at + 2] = colour & 0xff;
  };
  config.customColours.slice(0, 4).forEach((colour, i) => putColour(colour, 13 + i * 3));
  const [cold, mid, hot] = config.customRamp;
  // A stop's low two bits where version 1 had them; its third in byte 30.
  bytes[25] = (cold & 3) | ((mid & 3) << 2) | ((hot & 3) << 4);
  bytes[26] = config.ring5;
  putColour(config.customColours[4], 27);
  bytes[30] = (cold >> 2) | ((mid >> 2) << 1) | ((hot >> 2) << 2);
  bytes[31] = config.alwaysOnBoost;
  EXTRA_FIELDS.forEach(([key], i) => {
    bytes[32 + i] = config[key];
  });
  const crc = crc16(bytes, LENGTH - 2);
  bytes[LENGTH - 2] = crc >> 8;
  bytes[LENGTH - 1] = crc & 0xff;
  return bytes;
}

const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

/** base64url without padding: the canonical spelling. */
function toText(bytes: Uint8Array): string {
  let out = "";
  for (let i = 0; i < bytes.length; i += 3) {
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    const triple = (bytes[i] << 16) | (b1 << 8) | b2;
    out += ALPHABET[(triple >> 18) & 63] + ALPHABET[(triple >> 12) & 63];
    if (i + 1 < bytes.length) out += ALPHABET[(triple >> 6) & 63];
    if (i + 2 < bytes.length) out += ALPHABET[triple & 63];
  }
  return out;
}

function sextet(char: string): number {
  if (char === "+") return 62;
  if (char === "/") return 63;
  return ALPHABET.indexOf(char);
}

/** Either alphabet, padded or not, whitespace ignored; anything else refused. */
function fromText(code: string): Uint8Array {
  const text = code.replace(/\s+/g, "").replace(/=+$/, "");
  const values: number[] = [];
  for (const char of text) {
    const value = sextet(char);
    if (value < 0) throw new ConfigCodeError("not base64: contains characters outside the alphabet");
    values.push(value);
  }
  if (values.length % 4 === 1) throw new ConfigCodeError("not base64: impossible length");
  const bytes: number[] = [];
  for (let i = 0; i < values.length; i += 4) {
    const group = Math.min(4, values.length - i);
    let acc = 0;
    for (let k = 0; k < 4; k++) acc = (acc << 6) | (k < group ? values[i + k] : 0);
    bytes.push((acc >> 16) & 0xff);
    if (group > 2) bytes.push((acc >> 8) & 0xff);
    if (group > 3) bytes.push(acc & 0xff);
  }
  return Uint8Array.from(bytes);
}

export function encode(config: Config): string {
  return toText(toBytes(config));
}

/** Every field, or ConfigCodeError. A code is all-or-nothing. */
export function decode(code: string): Config {
  const bytes = fromText(code);
  if (bytes.length === 0) throw new ConfigCodeError("empty");
  const version = bytes[0];
  const length = LENGTHS[version] ?? 0;
  if (!length) throw new ConfigCodeError(`version ${version} is not one this page reads (1, 2, 3, 4)`);
  if (bytes.length !== length) throw new ConfigCodeError(`${bytes.length} bytes, a version-${version} code is ${length}`);
  const payload = length - 2;
  if (crc16(bytes, payload) !== ((bytes[payload] << 8) | bytes[payload + 1])) {
    throw new ConfigCodeError("checksum does not match: the code is damaged or mistyped");
  }
  const ramp = bytes[25];
  if (ramp >> 6) throw new ConfigCodeError("the ramp byte sets its reserved top bits");
  // Each later version's fields, or their defaults for an older code.
  const v2 = version >= 2;
  const high = v2 ? bytes[30] : 0;
  if (high >> 3) throw new ConfigCodeError("the ramp high byte sets its reserved bits");
  const colour = (at: number) => (bytes[at] << 16) | (bytes[at + 1] << 8) | bytes[at + 2];
  const stop = (s: number) => ((ramp >> (2 * s)) & 3) | (((high >> s) & 1) << 2);
  const config = {
    theme: bytes[1],
    ...Object.fromEntries(ENUM_FIELDS.map(([key], i) => [key, bytes[2 + i]])),
    ring5: v2 ? bytes[26] : DEFAULT_CONFIG.ring5,
    alwaysOnBoost: version >= 3 ? bytes[31] : DEFAULT_CONFIG.alwaysOnBoost,
    ...Object.fromEntries(EXTRA_FIELDS.map(([key], i) => [key, version >= 4 ? bytes[32 + i] : DEFAULT_CONFIG[key]])),
    tempAheadLow: bytes[11] - TEMP_OFFSET,
    tempAheadHigh: bytes[12] - TEMP_OFFSET,
    customColours: [colour(13), colour(16), colour(19), colour(22), v2 ? colour(27) : DEFAULT_CONFIG.customColours[4]],
    customRamp: [stop(0), stop(1), stop(2)],
  } as Config;
  const issues = problems(config);
  if (issues.length) throw new ConfigCodeError(issues.join("; "));
  return config;
}

/** decode() that reports rather than throws, for form inputs. */
export function tryDecode(code: string): { ok: true; config: Config } | { ok: false; reason: string } {
  try {
    return { ok: true, config: decode(code) };
  } catch (error) {
    return { ok: false, reason: error instanceof Error ? error.message : String(error) };
  }
}
