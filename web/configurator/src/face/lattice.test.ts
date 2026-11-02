import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import type { Device, Lattice } from "./lattice";

const read = <T>(name: string) =>
  JSON.parse(readFileSync(fileURLToPath(new URL(`../../public/geometry/${name}.json`, import.meta.url)), "utf8")) as T;

// theHubHasDotsOnlyWithoutHands: a watch with no hands keeps the hub's dots, in the
// innermost ring, so its centre ring draws as a disc; the Crossover's stays clear.
describe("the hub", () => {
  const devices = read<Device[]>("devices");

  it("is dotted exactly where a watch has no hands", () => {
    for (const device of devices) {
      const lattice = read<Lattice>(device.lattice);
      const inHub = lattice.dots.filter(([dx, dy]) => dx * dx + dy * dy < lattice.hub * lattice.hub);
      expect(lattice.hubDots).toBe(device.drawnHands);
      expect(inHub.length > 0).toBe(device.drawnHands);
      expect(inHub.every(([, , ring]) => ring === lattice.rings - 1)).toBe(true);
    }
  });

  it("gives the two 390 watches different lattices", () => {
    const of = (id: string) => devices.find((device) => device.id === id)!.lattice;
    expect(of("instinctcrossoveramoled")).toBe("390-hands");
    expect(of("epix2pro42mm")).toBe("390");
  });
});
