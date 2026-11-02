import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { type Config, ConfigCodeError, crc16, decode, encode } from "./configCode";

// The vectors all three codecs are held to; see docs/config-code.md.
const vectors = JSON.parse(
  readFileSync(fileURLToPath(new URL("../../../../tools/testdata/config-codes.json", import.meta.url)), "utf8"),
) as {
  crc_check: { input: string; crc: number };
  valid: { name: string; config: Config; code: string }[];
  v1: { name: string; config: Config; code: string }[];
  aliases: { name: string; code: string; same_as: string }[];
  invalid: { name: string; code: string }[];
};

describe("config code", () => {
  it("uses CRC-16/CCITT-FALSE", () => {
    const bytes = new TextEncoder().encode(vectors.crc_check.input);
    expect(crc16(bytes)).toBe(vectors.crc_check.crc);
  });

  for (const vector of vectors.valid) {
    it(`encodes ${vector.name}`, () => {
      expect(encode(vector.config)).toBe(vector.code);
      expect(vector.code).toHaveLength(44);
    });
    it(`decodes ${vector.name}`, () => {
      expect(decode(vector.code)).toEqual(vector.config);
    });
  }

  for (const vector of vectors.v1) {
    it(`reads the version-1 code ${vector.name}, defaulting what it lacks`, () => {
      expect(vector.code).toHaveLength(38);
      expect(decode(vector.code)).toEqual(vector.config);
    });
  }

  for (const alias of vectors.aliases) {
    it(`reads the ${alias.name} spelling`, () => {
      const target = vectors.valid.find((vector) => vector.name === alias.same_as)!;
      expect(decode(alias.code)).toEqual(target.config);
    });
  }

  for (const vector of vectors.invalid) {
    it(`refuses ${vector.name} whole`, () => {
      expect(() => decode(vector.code)).toThrow(ConfigCodeError);
    });
  }

  it("refuses a stray character rather than dropping it", () => {
    const code = vectors.valid[0].code;
    expect(() => decode(code.slice(0, 10) + "!" + code.slice(10))).toThrow(ConfigCodeError);
  });

  it("refuses to encode what it would refuse to decode", () => {
    expect(() => encode({ ...vectors.valid[0].config, theme: 5 })).toThrow(ConfigCodeError);
  });
});
