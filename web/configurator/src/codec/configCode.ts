// The config code: the face's whole configuration as one pasteable string.
//
// docs/config-code.md is the specification. This is one of three codecs held to
// tools/testdata/config-codes.json, beside tools/simctl/configcode.py and
// source/settings/ConfigCode.mc.

export const VERSION = 1;
export const LENGTH = 28;
const PAYLOAD = 26;
const TEMP_OFFSET = 20;

export const THEME_CUSTOM = 99;
export const THEME_IDS = [0, 1, 7, 8, THEME_CUSTOM] as const;
export const TEMP_MIN = -20;
export const TEMP_MAX = 50;
/** Source.COUNT - 1. The two time styles, 14 and 15, are the top. */
export const SOURCE_MAX = 15;

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
  tempAheadLow: number;
  tempAheadHigh: number;
  /** Four 0xRRGGBB colours, outermost ring first. */
  customColours: [number, number, number, number];
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
  tempAheadLow: 0,
  tempAheadHigh: 45,
  customColours: [0xe879f9, 0xb8d64b, 0x7fd4ff, 0xff6b5b],
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
  for (const [key, high] of ENUM_FIELDS) {
    if (!isByteInRange(config[key], high)) out.push(`${key} ${config[key]} is outside 0..${high}`);
  }
  for (const key of ["tempAheadLow", "tempAheadHigh"] as const) {
    const value = config[key];
    if (!Number.isInteger(value) || value < TEMP_MIN || value > TEMP_MAX) {
      out.push(`${key} ${value} is outside ${TEMP_MIN}..${TEMP_MAX}`);
    }
  }
  if (config.customColours.length !== 4 || !config.customColours.every((c) => isByteInRange(c, 0xffffff))) {
    out.push("customColours must be four 0xRRGGBB values");
  }
  if (config.customRamp.length !== 3 || !config.customRamp.every((s) => isByteInRange(s, 3))) {
    out.push("customRamp must be three indices 0..3");
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
  config.customColours.forEach((colour, i) => {
    bytes[13 + i * 3] = (colour >> 16) & 0xff;
    bytes[14 + i * 3] = (colour >> 8) & 0xff;
    bytes[15 + i * 3] = colour & 0xff;
  });
  const [cold, mid, hot] = config.customRamp;
  bytes[25] = cold | (mid << 2) | (hot << 4);
  const crc = crc16(bytes, PAYLOAD);
  bytes[26] = crc >> 8;
  bytes[27] = crc & 0xff;
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
  if (bytes[0] !== VERSION) throw new ConfigCodeError(`version ${bytes[0]} is not one this page reads (1)`);
  if (bytes.length !== LENGTH) throw new ConfigCodeError(`${bytes.length} bytes, a version-1 code is ${LENGTH}`);
  if (crc16(bytes, PAYLOAD) !== ((bytes[26] << 8) | bytes[27])) {
    throw new ConfigCodeError("checksum does not match: the code is damaged or mistyped");
  }
  const ramp = bytes[25];
  if (ramp >> 6) throw new ConfigCodeError("the ramp byte sets its reserved top bits");
  const colour = (i: number) => (bytes[13 + i * 3] << 16) | (bytes[14 + i * 3] << 8) | bytes[15 + i * 3];
  const config = {
    theme: bytes[1],
    ...Object.fromEntries(ENUM_FIELDS.map(([key], i) => [key, bytes[2 + i]])),
    tempAheadLow: bytes[11] - TEMP_OFFSET,
    tempAheadHigh: bytes[12] - TEMP_OFFSET,
    customColours: [colour(0), colour(1), colour(2), colour(3)],
    customRamp: [ramp & 3, (ramp >> 2) & 3, (ramp >> 4) & 3],
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
