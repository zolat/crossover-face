// A lattice exported by tools/geometry_export.py. Positions, rings and cross
// orientations come from there; GeometryTest.mc pins that export to DotGrid.
export interface Lattice {
  screen: number;
  /** Lattice columns (and rows): DotGrid.COLS. */
  cols: number;
  radius: number;
  hub: number;
  /** True where the hub has dots: a watch with no hands, whose innermost ring runs to the centre. */
  hubDots: boolean;
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
  /** The lattice file: the screen size, and `-hands` where the hub is kept clear for hands. */
  lattice: string;
  /** Lattice.RINGS: five on the 51mm, four elsewhere. */
  rings: number;
  drawnHands: boolean;
  /** The display's published diameter, for the real-size view. */
  displayMm: number;
}

const cache = new Map<string, Promise<Lattice>>();

/** A device's lattice by `Device.lattice`. A screen size is not enough: the Crossover and the 42mm Epix share 390. */
export function loadLattice(key: string, base = import.meta.env.BASE_URL): Promise<Lattice> {
  let found = cache.get(key);
  if (!found) {
    found = fetch(`${base}geometry/${key}.json?v=${__GEOMETRY_VERSION__}`).then((response) => {
      if (!response.ok) throw new Error(`no lattice ${key}: ${response.status}`);
      return response.json() as Promise<Lattice>;
    });
    cache.set(key, found);
  }
  return found;
}

export async function loadDevices(base = import.meta.env.BASE_URL): Promise<Device[]> {
  const response = await fetch(`${base}geometry/devices.json?v=${__GEOMETRY_VERSION__}`);
  return (await response.json()) as Device[];
}
