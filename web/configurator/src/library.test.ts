import { describe, expect, it } from "vitest";
import { DEFAULT_CONFIG, encode, THEME_CUSTOM } from "./codec/configCode";
import { type Backing, createLibrary } from "./library";
import { importMessage } from "./ui/library";

const memory = (initial: string | null = null): Backing & { text: string | null } => {
  const store = {
    text: initial,
    read: () => store.text,
    write: (text: string) => { store.text = text; },
  };
  return store;
};

const A = encode(DEFAULT_CONFIG);
const B = encode({ ...DEFAULT_CONFIG, theme: THEME_CUSTOM, customColours: [0xff0000, 0x00ff00, 0x0000ff, 0xffff00] });
let tick = 0;
const clock = () => new Date(Date.UTC(2026, 10, 1, 12, 0, tick++));

describe("saved configs", () => {
  it("adds, renames and removes, and keeps them across a reload", () => {
    const backing = memory();
    const library = createLibrary(backing, clock);
    const first = library.add("Terrain", A, "instinctcrossoveramoled");
    library.add("Primaries", B, "epix2pro51mm");
    expect(library.list().map((entry) => entry.name)).toEqual(["Primaries", "Terrain"]);
    library.rename(first.id, "  Everyday  ");
    expect(createLibrary(backing, clock).list().map((entry) => entry.name)).toEqual(["Primaries", "Everyday"]);
    const removed = library.remove(first.id)!;
    expect(library.list()).toHaveLength(1);
    library.restore(removed);
    expect(library.list().map((entry) => entry.name)).toEqual(["Primaries", "Everyday"]);
  });

  it("refuses to save a code that does not decode", () => {
    expect(() => createLibrary(memory(), clock).add("Bad", A.slice(0, 10) + (A[10] === "A" ? "B" : "A") + A.slice(11), "epix2")).toThrow();
  });

  it("round-trips through a file into another browser", () => {
    const library = createLibrary(memory(), clock);
    library.add("Terrain", A, "instinctcrossoveramoled");
    library.add("Primaries", B, "epix2pro51mm");
    const elsewhere = createLibrary(memory(), clock);
    expect(elsewhere.importFile(library.exportFile())).toEqual({ added: 2, duplicates: 0, invalid: 0 });
    expect(elsewhere.list().map(({ name, code, device }) => ({ name, code, device })))
      .toEqual(library.list().map(({ name, code, device }) => ({ name, code, device })));
  });

  it("skips duplicates and damaged codes on import, and says how many", () => {
    const library = createLibrary(memory(), clock);
    library.add("Terrain", A, "instinctcrossoveramoled");
    const file = JSON.stringify({ format: "crossover-face-library", version: 1, configs: [
      { name: "Terrain", code: A, device: "instinctcrossoveramoled" },
      { name: "Broken", code: "AAAA", device: "epix2" },
      { name: 7, code: B, device: "epix2" },
      { name: "Primaries", code: B, device: "epix2" },
    ] });
    expect(library.importFile(file)).toEqual({ added: 1, duplicates: 1, invalid: 2 });
  });

  it("refuses a file that is not a library, or is from a newer page", () => {
    const library = createLibrary(memory(), clock);
    expect(() => library.importFile("{}")).toThrow("not a saved-configs file");
    expect(() => library.importFile("not json")).toThrow("not a saved-configs file");
    expect(() => library.importFile(JSON.stringify({ format: "crossover-face-library", version: 2, configs: [] })))
      .toThrow("newer version");
  });

  it("keeps working when the browser refuses storage", () => {
    const blocked: Backing = { read: () => { throw new Error("denied"); }, write: () => { throw new Error("denied"); } };
    const library = createLibrary(blocked, clock);
    expect(library.persistent).toBe(false);
    library.add("Terrain", A, "epix2");
    expect(library.list()).toHaveLength(1);
    expect(library.persistent).toBe(false);
  });

  it("drops stored entries that are malformed or no longer decode", () => {
    const backing = memory(JSON.stringify([
      { id: "1", name: "Good", code: A, device: "epix2", savedAt: "2026-11-01T00:00:00Z" },
      { id: "2", name: "Bad", code: "AAAA", device: "epix2", savedAt: "2026-11-01T00:00:00Z" },
      "nonsense",
    ]));
    expect(createLibrary(backing, clock).list().map((entry) => entry.name)).toEqual(["Good"]);
  });

  it("says what an import did in words", () => {
    expect(importMessage({ added: 2, duplicates: 0, invalid: 0 })).toBe("Added 2 configs.");
    expect(importMessage({ added: 0, duplicates: 2, invalid: 0 })).toBe("Nothing new to add; 2 were already saved.");
    expect(importMessage({ added: 1, duplicates: 1, invalid: 1 })).toBe("Added 1 config; 1 was already saved and 1 was damaged.");
  });
});
