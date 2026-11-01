import "./styles.css";
import { loadDevices } from "./face/lattice";
import { schema } from "./face/schema";
import { createStore, DEFAULT_DEVICE, initialConfig, readHash, remembered } from "./state";
import { mountApp } from "./ui/app";
import { tryDecode } from "./codec/configCode";

async function start() {
  const root = document.getElementById("app")!;
  const devices = await loadDevices();
  const fromLink = readHash(location.hash);
  const fromLast = remembered.load();
  const deviceId = [fromLink.device, fromLast.device, DEFAULT_DEVICE].find((id) => devices.some((d) => d.id === id))!;
  const device = devices.find((d) => d.id === deviceId)!;
  const last = fromLast.code ? tryDecode(fromLast.code) : null;
  const config = fromLink.config ?? (last?.ok ? last.config : initialConfig(device.drawnHands, schema.defaultsDrawn));
  const store = createStore({ device: deviceId, config, mode: "awake" });
  mountApp(root, store, devices);
  if (fromLink.error) console.warn(`the link's code did not load: ${fromLink.error}`);
}

void start();
