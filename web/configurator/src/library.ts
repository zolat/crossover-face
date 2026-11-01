// Configs saved in this browser, by name. Nothing here reaches the watch: an entry is a
// config code and the watch it was made for, and loading one only changes the page.
//
// An entry keeps the code rather than the decoded config, so there is one format for a
// config wherever it travels, and every load or import checks it with the same decoder.
import { tryDecode } from "./codec/configCode";

export interface Saved {
  id: string;
  name: string;
  code: string;
  device: string;
  savedAt: string;
}

/** Where the library lives. localStorage in the page, a plain object in tests. */
export interface Backing {
  read(): string | null;
  write(text: string): void;
}

export const EXPORT_FORMAT = "crossover-face-library";
export const EXPORT_VERSION = 1;
const STORAGE_KEY = "crossover-face-library";

export const localBacking: Backing = {
  read: () => localStorage.getItem(STORAGE_KEY),
  write: (text) => localStorage.setItem(STORAGE_KEY, text),
};

export interface ImportResult {
  added: number;
  duplicates: number;
  invalid: number;
}

function wellFormed(entry: unknown): entry is Omit<Saved, "id"> & { id?: string } {
  if (!entry || typeof entry !== "object") return false;
  const { name, code, device, savedAt } = entry as Record<string, unknown>;
  return typeof name === "string" && typeof code === "string" && typeof device === "string" &&
    (savedAt === undefined || typeof savedAt === "string");
}

let counter = 0;
const newId = () => `${Date.now().toString(36)}-${(++counter).toString(36)}-${Math.random().toString(36).slice(2, 7)}`;

export function createLibrary(backing: Backing, now: () => Date = () => new Date()) {
  let entries: Saved[] = [];
  /** False when the browser refuses storage: the library still works for this visit. */
  let persistent = true;

  try {
    const parsed = JSON.parse(backing.read() ?? "[]");
    if (Array.isArray(parsed)) {
      entries = parsed.filter(wellFormed).filter((entry) => tryDecode(entry.code).ok)
        .map((entry) => ({ ...entry, id: entry.id ?? newId(), savedAt: entry.savedAt ?? now().toISOString() }));
    }
  } catch {
    persistent = false;
  }

  function persist() {
    try {
      backing.write(JSON.stringify(entries));
      persistent = true;
    } catch {
      persistent = false;
    }
  }

  return {
    list: (): readonly Saved[] => entries,
    get persistent() {
      return persistent;
    },

    add(name: string, code: string, device: string): Saved {
      if (!tryDecode(code).ok) throw new Error("not a valid config code");
      const entry: Saved = { id: newId(), name: name.trim() || "Untitled", code, device, savedAt: now().toISOString() };
      entries = [entry, ...entries];
      persist();
      return entry;
    },

    rename(id: string, name: string) {
      entries = entries.map((entry) => (entry.id === id ? { ...entry, name: name.trim() || entry.name } : entry));
      persist();
    },

    /** Removes an entry and returns it, so it can be put back. */
    remove(id: string): Saved | null {
      const found = entries.find((entry) => entry.id === id) ?? null;
      entries = entries.filter((entry) => entry.id !== id);
      persist();
      return found;
    },

    /** Puts a removed entry back where it was by date. */
    restore(entry: Saved) {
      if (entries.some((existing) => existing.id === entry.id)) return;
      entries = [...entries, entry].sort((a, b) => b.savedAt.localeCompare(a.savedAt));
      persist();
    },

    exportFile(): string {
      const configs = entries.map(({ name, code, device, savedAt }) => ({ name, code, device, savedAt }));
      return JSON.stringify({ format: EXPORT_FORMAT, version: EXPORT_VERSION, configs }, null, 2) + "\n";
    },

    /** Merges a file's configs in. Throws only when the file is not a library at all. */
    importFile(text: string): ImportResult {
      let parsed: unknown;
      try {
        parsed = JSON.parse(text);
      } catch {
        throw new Error("that file is not a saved-configs file");
      }
      const file = parsed as { format?: unknown; version?: unknown; configs?: unknown };
      if (file?.format !== EXPORT_FORMAT || !Array.isArray(file.configs)) {
        throw new Error("that file is not a saved-configs file");
      }
      if (typeof file.version !== "number" || file.version > EXPORT_VERSION) {
        throw new Error("that file was made by a newer version of this page");
      }
      const result: ImportResult = { added: 0, duplicates: 0, invalid: 0 };
      const added: Saved[] = [];
      for (const entry of file.configs) {
        if (!wellFormed(entry) || !tryDecode(entry.code).ok) {
          result.invalid++;
          continue;
        }
        const duplicate = [...entries, ...added].some((existing) => existing.name === entry.name && existing.code === entry.code);
        if (duplicate) {
          result.duplicates++;
          continue;
        }
        added.push({ id: newId(), name: entry.name, code: entry.code, device: entry.device,
          savedAt: entry.savedAt ?? now().toISOString() });
        result.added++;
      }
      if (added.length) {
        entries = [...entries, ...added].sort((a, b) => b.savedAt.localeCompare(a.savedAt));
        persist();
      }
      return result;
    },
  };
}

export type Library = ReturnType<typeof createLibrary>;
