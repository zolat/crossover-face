// A lattice exported by tools/geometry_export.py. Positions, rings and cross
// orientations come from there; GeometryTest.mc pins that export to DotGrid.
export interface Lattice {
  screen: number;
  /** Lattice columns (and rows): DotGrid.COLS. */
  cols: number;
  radius: number;
  hub: number;
  pitch: number;
  dot: number;
  rings: number;
  ringEdges: number[];
  ringCounts: number[];
  arms: [number, number, number, number][];
  /** [dx, dy, ring, orientation, turn] per dot, turn clockwise from twelve. */
  dots: [number, number, number, number, number][];
}

export interface Device {
  id: string;
  screen: number;
  drawnHands: boolean;
  /** The display's published diameter, for the real-size view. */
  displayMm: number;
}

const cache = new Map<number, Promise<Lattice>>();

export function loadLattice(screen: number, base = import.meta.env.BASE_URL): Promise<Lattice> {
  let found = cache.get(screen);
  if (!found) {
    found = fetch(`${base}geometry/${screen}.json`).then((response) => {
      if (!response.ok) throw new Error(`no lattice for ${screen}: ${response.status}`);
      return response.json() as Promise<Lattice>;
    });
    cache.set(screen, found);
  }
  return found;
}

export async function loadDevices(base = import.meta.env.BASE_URL): Promise<Device[]> {
  const response = await fetch(`${base}geometry/devices.json`);
  return (await response.json()) as Device[];
}
