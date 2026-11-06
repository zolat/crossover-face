// End-to-end check of the built configurator in the machine's own Chrome.
//
// Every expected code is produced by the *Python* codec (tools/simctl/configcode.py),
// not by the page's own TypeScript, so a check that passes means two independent codecs
// agree on what the page produced. Run with `npm run e2e`; screenshots land in
// E2E_SHOTS (default: e2e/shots, gitignored).
import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, "../../..");
const shots = process.env.E2E_SHOTS ?? join(here, "shots");
const chrome = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const port = 4319;
const origin = `http://localhost:${port}`;
mkdirSync(shots, { recursive: true });

const PAGE_START = { ring2: 6 };
function python(config) {
  return execFileSync("python3", ["-m", "simctl.configcode", "encode", JSON.stringify(config)], {
    cwd: repo, env: { ...process.env, PYTHONPATH: join(repo, "tools") }, encoding: "utf8",
  }).trim();
}

function decoded(code) {
  return JSON.parse(execFileSync("python3", ["-m", "simctl.configcode", "decode", code], {
    cwd: repo, env: { ...process.env, PYTHONPATH: join(repo, "tools") }, encoding: "utf8",
  }));
}

let failures = 0;
function check(name, ok, detail = "") {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${ok || !detail ? "" : `  (${detail})`}`);
  if (!ok) failures++;
}

const server = spawn("npx", ["vite", "preview", "--port", String(port), "--strictPort"], { cwd: resolve(here, ".."), stdio: "ignore" });
for (let i = 0; i < 50; i++) {
  try { if ((await fetch(origin)).ok) break; } catch { /* not up yet */ }
  await new Promise((r) => setTimeout(r, 200));
}

const browser = await puppeteer.launch({ executablePath: chrome, headless: true, args: ["--no-first-run"] });
try {
  await browser.defaultBrowserContext().overridePermissions(origin, ["clipboard-read", "clipboard-write", "clipboard-sanitized-write"]);
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  page.on("console", (message) => { if (message.type() === "error") errors.push(message.text()); });
  page.on("response", (response) => { if (response.status() >= 400) errors.push(`${response.status()} ${response.url()}`); });
  await page.setViewport({ width: 1440, height: 1000, deviceScaleFactor: 2 });
  // Start from an empty browser once; reloads below must keep what the page saved.
  await page.goto(origin + "/", { waitUntil: "networkidle0" });
  await page.evaluate(() => localStorage.clear());
  await page.reload({ waitUntil: "networkidle0" });

  const code = () => page.$eval(".code output", (el) => el.textContent);
  const pickLabel = async (text) => {
    const labels = await page.$$("label");
    for (const label of labels) {
      if ((await label.evaluate((el) => el.textContent.trim())) === text) { await label.click(); return; }
    }
    throw new Error(`no label ${text}`);
  };
  // Read the face at the watch's resolution, whatever the canvas is scaled by.
  const pixel = (x, y) => page.$eval("canvas.face", (canvas, x, y) => {
    const k = canvas.width / 390;
    const [r, g, b] = canvas.getContext("2d").getImageData(x * k, y * k, 1, 1).data;
    return (r << 16) | (g << 8) | b;
  }, x, y);
  // The outermost row's dot at dx=5, dy=-185: ring 0, a hair past twelve, lit by Steps.
  const topDot = [195 + 5, 195 - 185];

  check("opens on the page's starting config", (await code()) === python(PAGE_START), await code());
  check("draws the 390 lattice for the Crossover", (await page.$eval("canvas.face", (c) => c.width % 390 === 0 && c.width / c.height === 1)));
  check("ring 1 lit dot is Terrain orchid", (await pixel(...topDot)) === 0xe879f9);
  await page.screenshot({ path: join(shots, "desktop-terrain.png") });

  const litPixels = () => page.$eval("canvas.face", (canvas) => {
    const { data } = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height);
    let count = 0;
    for (let i = 0; i < data.length; i += 4) if (data[i] | data[i + 1] | data[i + 2]) count++;
    return count;
  });
  const pickIn = async (legend, text) => {
    const fieldsets = await page.$$("fieldset");
    for (const fieldset of fieldsets) {
      if ((await fieldset.$eval("legend", (el) => el.textContent.trim()).catch(() => "")) !== legend) continue;
      for (const label of await fieldset.$$("label")) {
        if ((await label.evaluate((el) => el.textContent.trim())) === text) { await label.click(); return; }
      }
    }
    throw new Error(`no ${legend}: ${text}`);
  };
  const withDate = await litPixels();
  await pickIn("Date", "Off");
  const withoutDate = await litPixels();
  check("the date's outline is drawn, and goes with the setting", withDate > withoutDate, `${withDate} vs ${withoutDate}`);
  await pickIn("Date", "On");
  await pickLabel("Always-on");
  const asleepWith = await litPixels();
  await pickIn("Date", "Off");
  check("always-on carries no date", (await litPixels()) === asleepWith);
  await pickIn("Date", "On");
  await pickLabel("Awake");

  const faceWidth = () => page.$eval("canvas.face", (c) => c.getBoundingClientRect().width);
  check("a large face is a whole number of device pixels per watch pixel", Number.isInteger((await faceWidth()) * 2 / 390), `${await faceWidth()}`);
  await pickLabel("Real size");
  const estimated = await faceWidth();
  check("real size draws the 30.48 mm display at the estimate", Math.abs(estimated - 30.48 * 120 / 25.4) < 0.5, `${estimated}`);
  await page.click(".size button");
  check("setting it shows a card outline", await page.$eval(".card", (el) => !el.hidden && el.getBoundingClientRect().width > 300));
  await page.$eval("#calibrate", (input) => { input.value = "6"; input.dispatchEvent(new Event("input", { bubbles: true })); });
  await page.click(".size .primary");
  check("a card calibration sets the real size", Math.abs((await faceWidth()) - 30.48 * 6) < 0.5, `${await faceWidth()}`);
  await pickLabel("Large");

  await pickLabel("Beacon");
  check("choosing Beacon changes the code", (await code()) === python({ ...PAGE_START, theme: 7 }), await code());
  check("…and the drawn colour", (await pixel(...topDot)) === 0x5cd9f0);

  await page.select(".rings .ring:nth-child(2) select", "7");
  check("ring 2 to Seconds", (await code()) === python({ ...PAGE_START, theme: 7, ring2: 7 }), await code());

  await pickLabel("Always-on");
  check("always-on keeps a lit dot at full band", (await pixel(...topDot)) === 0x5cd9f0);
  check("always-on leaves the code alone", (await code()) === python({ ...PAGE_START, theme: 7, ring2: 7 }));

  // The always-on boost: lighter always-on colours, awake untouched, carried in the code.
  const near = (a, b) => [16, 8, 0].every((shift) => Math.abs(((a >> shift) & 255) - ((b >> shift) & 255)) <= 1);
  const meterFigure = () => page.$eval(".meter span", (el) => parseFloat(el.textContent.replace(/^[^\d]*/, "")));
  check("always-on brightness starts at Normal", await page.$$eval("fieldset", (sets) => {
    const set = sets.find((f) => f.querySelector("legend")?.textContent.trim() === "Always-on brightness");
    return set?.querySelector("input:checked + label")?.textContent.trim() === "Normal";
  }));
  const plainFigure = await meterFigure();
  await pickIn("Always-on brightness", "Brightest");
  check("Brightest puts the boost in the code",
    (await code()) === python({ ...PAGE_START, theme: 7, ring2: 7, alwaysOnBoost: 2 }) && decoded(await code()).alwaysOnBoost === 2,
    await code());
  const boosted = await pixel(...topDot);
  check("…and draws always-on in the lightened colour (mockup.lighten, Beacon cyan)", near(boosted, 0xc3f5ff), boosted.toString(16));
  const boostedFigure = await meterFigure();
  check("…which the brightness figure prices, still under 10%", boostedFigure > plainFigure && boostedFigure < 10,
    `${plainFigure} -> ${boostedFigure}`);
  await page.screenshot({ path: join(shots, "desktop-always-on-brightest.png") });
  await pickLabel("Awake");
  check("…and leaves the awake face alone", (await pixel(...topDot)) === 0x5cd9f0);
  await pickIn("Always-on brightness", "Normal");
  check("Normal takes the boost back out", (await code()) === python({ ...PAGE_START, theme: 7, ring2: 7 }), await code());

  await pickLabel("Make your own");
  check("Make your own selects theme 99", (await code()) === python({ ...PAGE_START, theme: 99, ring2: 7 }), await code());
  const hexOf = (colour) => `#${colour.toString(16).padStart(6, "0")}`;
  const typeHex = (target, value) => target.$eval(".hex", (input, text) => {
    input.value = text;
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }, value);
  const grey = (colour) => ((colour >> 16) & 255) === ((colour >> 8) & 255) && ((colour >> 8) & 255) === (colour & 255);
  check("the builder edits one ring at a time on a wheel",
    (await page.$$(".ring-tab")).length === 4 && (await page.$$(".wheel-disc")).length === 1);
  check("dull colours are hidden by default", await page.$eval('[data-key="hide-dull"]', (box) => box.checked));
  await page.$eval('label[for="colour-1"]', (label) => label.click());
  await typeHex(page, "#050505");
  const brightened = decoded(await code()).customColours[1];
  check("a dull colour typed in is brightened to one the watch shows",
    brightened !== 0x050505 && brightened !== 0xb8d64b && (await page.$eval(".hex", (el) => el.value.toLowerCase())) === hexOf(brightened),
    hexOf(brightened));
  check("…and says so", (await page.$eval(".wheel-note", (el) => el.textContent)).includes("brightened"));
  const disc = await page.$(".wheel-disc");
  await disc.evaluate((el) => el.scrollIntoView({ block: "center" }));
  const wheelBox = await disc.boundingBox();
  await page.mouse.click(wheelBox.x + wheelBox.width / 2, wheelBox.y + wheelBox.height / 2);
  const middle = decoded(await code()).customColours[1];
  check("clicking the wheel's grey middle picks a colour, not a grey", !grey(middle) && middle !== brightened, hexOf(middle));
  await page.mouse.move(wheelBox.x + wheelBox.width * 0.85, wheelBox.y + wheelBox.height * 0.5);
  await page.mouse.down();
  for (let step = 1; step <= 8; step++) {
    await page.mouse.move(wheelBox.x + wheelBox.width * 0.85, wheelBox.y + wheelBox.height * (0.5 + step * 0.04));
  }
  await page.mouse.up();
  const dragged = decoded(await code());
  check("dragging on the wheel recolours only that ring", dragged.customColours[1] !== middle &&
    python({ ...dragged, customColours: [...dragged.customColours.slice(0, 1), middle, ...dragged.customColours.slice(2)] }) ===
      python({ ...PAGE_START, theme: 99, ring2: 7, customColours: [0xe879f9, middle, 0x7fd4ff, 0xff6b5b, 0xe5b33a] }),
    hexOf(dragged.customColours[1]));
  check("the wheel is not rebuilt under the pointer", await disc.evaluate((el) => el.isConnected));
  check("…and the preview follows it", (await page.$eval('label[for="colour-1"] i', (el) => getComputedStyle(el).backgroundColor)) ===
    `rgb(${(dragged.customColours[1] >> 16) & 255}, ${(dragged.customColours[1] >> 8) & 255}, ${dragged.customColours[1] & 255})`);
  await page.screenshot({ path: join(shots, "desktop-wheel.png") });

  await page.click('[data-key="hide-dull"]');
  await typeHex(page, "#050505");
  const colours = [0xe879f9, 0x050505, 0x7fd4ff, 0xff6b5b, 0xe5b33a];
  check("with dull colours shown, any colour reaches the code",
    (await code()) === python({ ...PAGE_START, theme: 99, ring2: 7, customColours: colours }), await code());
  check("…and the wheel says it is dull", (await page.$eval(".wheel-note", (el) => el.textContent)).includes("dull"));
  const warnings = await page.$$eval(".warnings p", (ps) => ps.map((p) => p.textContent));
  check("a too-dark colour is warned about", warnings.some((text) => text.includes("ring 2 is very dark")), warnings.join(" | "));
  await page.reload({ waitUntil: "networkidle0" });
  check("the page remembers dull colours are shown", !(await page.$eval('[data-key="hide-dull"]', (box) => box.checked)));
  check("…and which colours were picked", (await code()) === python({ ...PAGE_START, theme: 99, ring2: 7, customColours: colours }));
  await page.select("#stop-0", "1");
  check("a ramp stop reaches the code",
    (await code()) === python({ ...PAGE_START, theme: 99, ring2: 7, customColours: colours, customRamp: [1, 0, 3] }), await code());
  await page.screenshot({ path: join(shots, "desktop-custom.png") });

  const beforeRandom = await code();
  await page.click(".randomise");
  const randomised = await code();
  const decodedRandom = JSON.parse(execFileSync("python3", ["-m", "simctl.configcode", "decode", randomised], {
    cwd: repo, env: { ...process.env, PYTHONPATH: join(repo, "tools") }, encoding: "utf8" }));
  check("Randomise colours gives a new custom theme", randomised !== beforeRandom && decodedRandom.theme === 99, randomised);
  check("…that nothing warns about", (await page.$$(".warnings p")).length === 0);
  check("…and keeps focus on the button", await page.evaluate(() => document.activeElement?.classList.contains("randomise")));
  check("…and changes nothing but the colours", randomised !== beforeRandom &&
    python({ ...decodedRandom, customColours: colours, customRamp: [1, 0, 3] }) === beforeRandom);
  await page.screenshot({ path: join(shots, "desktop-random.png") });

  // A duo-tone candidate is a custom theme of two colours, alternating outside in, with
  // the ramp from the bluer to the warmer; the Python codec is what says so.
  await pickLabel("Ember & Ice");
  const duo = decoded(await code());
  check("A duo-tone candidate loads as the custom theme",
    duo.theme === 99 && duo.customColours.join() === [0xff7a3d, 0x6fd3ff, 0xff7a3d, 0x6fd3ff, 0xff7a3d].join() &&
    duo.customRamp.join() === "1,0,2", JSON.stringify(duo));
  check("…changes nothing but the colours", python({ ...duo, customColours: decodedRandom.customColours,
    customRamp: decodedRandom.customRamp }) === randomised);
  check("…draws the outer ring in its first colour", (await pixel(...topDot)) === 0xff7a3d);
  check("…and shows which candidate it is", await page.$$eval("input[type=radio]:checked + label",
    (labels) => labels.some((label) => label.textContent.trim() === "Ember & Ice")));
  check("…that nothing warns about", (await page.$$(".warnings p")).length === 0);
  await page.screenshot({ path: join(shots, "desktop-duotone.png") });

  await page.click(".actions .primary");
  await new Promise((r) => setTimeout(r, 200));
  check("Copy code puts the code on the clipboard",
    (await page.evaluate(() => navigator.clipboard.readText())) === (await code()));

  // From the vectors all three codecs are held to: a version-2 code, another spelling of
  // it, and the same face as a version-1 code, which the page reads and re-writes as 2.
  const vectors = JSON.parse(readFileSync(resolve(repo, "tools/testdata/config-codes.json"), "utf8"));
  const vector = vectors.valid.find((v) => v.name === "custom-theme-every-field-moved").code;
  const spelled = vectors.aliases.find((a) => a.name === "standard-alphabet-with-padding").code;
  const older = vectors.v1.find((v) => v.name === "custom-theme-every-field-moved").code;
  const loadCode = async () => {
    for (const button of await page.$$(".actions button")) {
      if ((await button.evaluate((el) => el.textContent.trim())) === "Load a code") return button;
    }
    throw new Error("no Load a code button");
  };
  await (await loadCode()).click();
  await page.type("#paste", spelled);
  await page.click(".paste button");
  check("a pasted code loads, spelled either way", (await code()) === vector, await code());
  check("…and closes the paste box", (await page.$("#paste")) === null);
  await (await loadCode()).click();
  await page.type("#paste", older);
  await page.click(".paste button");
  check("a version-1 code loads, and comes back as version 2", (await code()) === vector, await code());

  const before = await code();
  await (await loadCode()).click();
  await page.type("#paste", vector.slice(0, -1) + "x");
  await page.click(".paste button");
  const error = await page.$eval(".error", (el) => el.textContent).catch(() => "");
  check("a damaged code is refused with a reason", error.includes("checksum"), error);
  check("…and changes nothing", (await code()) === before);

  // --- saved configs ---------------------------------------------------------
  const savedNames = () => page.$$eval(".saved .entry .name", (els) => els.map((el) => el.textContent));
  const savedCode = await code();
  await page.click('[data-key="save"]');
  await page.$eval("#save-name", (input) => { input.value = ""; });
  await page.type("#save-name", "Mine");
  await page.keyboard.press("Enter");
  check("Save keeps the config in the list", JSON.stringify(await savedNames()) === '["Mine"]', JSON.stringify(await savedNames()));
  await page.reload({ waitUntil: "networkidle0" });
  check("…and it is still there after a reload", JSON.stringify(await savedNames()) === '["Mine"]');
  await pickLabel("Activity");
  await page.select(".rings .ring:nth-child(1) select", "4");
  check("…while the page has moved on", (await code()) !== savedCode);
  await page.click(".saved .entry .load");
  check("Load restores the exact code", (await code()) === savedCode, await code());
  check("…marks the row as showing", (await page.$$(".saved .entry.showing")).length === 1);

  await page.click('.saved [data-key^="rename-btn-"]');
  await page.$eval(".rename input", (input) => { input.value = ""; });
  await page.type(".rename input", "Renamed");
  await page.keyboard.press("Enter");
  check("Rename renames", JSON.stringify(await savedNames()) === '["Renamed"]', JSON.stringify(await savedNames()));
  await page.click('.saved [data-key^="delete-"]');
  check("Delete removes it", (await savedNames()).length === 0);
  await page.click('.saved [data-key="undo"]');
  check("…and Undo puts it back", JSON.stringify(await savedNames()) === '["Renamed"]');

  // A second entry, on another watch, so the file carries more than one.
  await page.goto(`${origin}/#c=${vector}&w=epix2pro51mm`, { waitUntil: "networkidle0" });
  await page.reload({ waitUntil: "networkidle0" });
  await page.click('[data-key="save"]');
  await page.keyboard.press("Enter");
  const library = await page.evaluate(() => JSON.parse(localStorage.getItem("crossover-face-library")));
  check("a second save lands on top, with its watch", library.length === 2 && library[0].device === "epix2pro51mm" && library[0].code === vector);

  const downloads = join(shots, "downloads");
  rmSync(downloads, { recursive: true, force: true });
  mkdirSync(downloads, { recursive: true });
  const cdp = await page.createCDPSession();
  await cdp.send("Browser.setDownloadBehavior", { behavior: "allow", downloadPath: downloads });
  await page.click('.saved [data-key="export"]');
  const exported = join(downloads, "crossover-face-configs.json");
  for (let i = 0; i < 50 && !existsSync(exported); i++) await new Promise((r) => setTimeout(r, 100));
  const file = existsSync(exported) ? JSON.parse(readFileSync(exported, "utf8")) : null;
  check("Export all downloads the library as a file", file?.format === "crossover-face-library" && file.configs.length === 2);
  const pythonAgrees = file?.configs.every((entry) => {
    const config = JSON.parse(execFileSync("python3", ["-m", "simctl.configcode", "decode", entry.code], {
      cwd: repo, env: { ...process.env, PYTHONPATH: join(repo, "tools") }, encoding: "utf8" }));
    return python(config) === entry.code;
  });
  check("…whose codes the Python codec reads back exactly", pythonAgrees === true);

  const fresh = await browser.createBrowserContext();
  const other = await fresh.newPage();
  other.on("pageerror", (error) => errors.push(String(error)));
  await other.goto(origin + "/", { waitUntil: "networkidle0" });
  check("a fresh browser starts with nothing saved", (await other.$$(".saved .entry")).length === 0);
  await (await other.$("#import-file")).uploadFile(exported);
  await other.waitForSelector(".saved .entry:nth-child(2)", { timeout: 3000 }).catch(() => {});
  const imported = await other.evaluate(() => JSON.parse(localStorage.getItem("crossover-face-library") ?? "[]"));
  check("Import restores every entry, codes identical",
    JSON.stringify(imported.map(({ name, code, device }) => [name, code, device])) ===
    JSON.stringify(file?.configs.map(({ name, code, device }) => [name, code, device])), JSON.stringify(imported));
  const status = await other.$eval(".saved .status", (el) => el.textContent);
  check("…and says what it did", status === "Added 2 configs.", status);
  await (await other.$("#import-file")).uploadFile(exported);
  await new Promise((r) => setTimeout(r, 300));
  check("importing again skips what is already saved",
    (await other.$eval(".saved .status", (el) => el.textContent)).includes("2 were already saved") &&
    (await other.$$(".saved .entry")).length === 2);
  await other.screenshot({ path: join(shots, "desktop-saved.png"), fullPage: true });
  await fresh.close();

  await page.goto(`${origin}/#c=${vector}&w=epix2pro51mm`, { waitUntil: "networkidle0" });
  await page.reload({ waitUntil: "networkidle0" });
  check("a link opens on its code", (await code()) === vector);
  check("…and its watch", (await page.$eval("canvas.face", (c) => c.width % 454 === 0)));
  check("…and no Hands setting, since the Epix has no hands to back",
    !(await page.content()).includes("Behind hands"));

  // The Epix tells the time in its outer ring: placed, not chosen, and in the code as
  // the watch itself publishes it.
  const epixContext = await browser.createBrowserContext();
  const epix = await epixContext.newPage();
  epix.on("pageerror", (error) => errors.push(String(error)));
  await epix.goto(`${origin}/#w=epix2`, { waitUntil: "networkidle0" });
  const epixCode = () => epix.$eval(".code output", (el) => el.textContent);
  check("a fresh Epix starts on the overlap time style", decoded(await epixCode()).ring1 === 15, await epixCode());
  const timeOptions = await epix.$$eval(".rings .ring:nth-child(1) option", (options) => options.map((o) => o.textContent));
  check("its outer ring offers the time styles and nothing else",
    JSON.stringify(timeOptions) === JSON.stringify(["Time: overlap", "Time: split"]), JSON.stringify(timeOptions));
  // A ring-0 dot just past twelve: inside both fills at ten past ten.
  const grid416 = JSON.parse(readFileSync(resolve(here, "../public/geometry/416.json"), "utf8"));
  const [tdx, tdy] = grid416.dots.filter(([, , ring, , turn]) => ring === 0 && turn > 0.02 && turn < 0.1)[0];
  const epixPixel = () => epix.$eval("canvas.face", (canvas, x, y) => {
    const k = canvas.width / 416;
    const [r, g, b] = canvas.getContext("2d").getImageData((208 + x) * k, (208 + y) * k, 1, 1).data;
    return (r << 16) | (g << 8) | b;
  }, tdx, tdy);
  check("the preview draws the time: the ring's own colour where hour and minute have both passed",
    (await epixPixel()) === 0xe879f9, (await epixPixel()).toString(16));
  await epix.select(".rings .ring:nth-child(1) select", "14");
  check("choosing split puts 14 in the code", decoded(await epixCode()).ring1 === 14);
  check("…and draws it white", (await epixPixel()) === 0xffffff, (await epixPixel()).toString(16));
  await epix.screenshot({ path: join(shots, "desktop-epix-time.png") });
  await epix.select(".rings .ring:nth-child(1) select", "15");

  // The time ring's extras: a row each, on a watch with a time ring only. A solid cell
  // lights all 25 pixels of its 5x5 square; a cross lights 9.
  const solidCellsNear = (turn) => epix.$eval("canvas.face", (canvas, cells) => {
    const k = canvas.width / 416;
    const { data } = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height);
    const lit = (x, y) => {
      const at = (Math.round(y * k) * canvas.width + Math.round(x * k)) * 4;
      return data[at] + data[at + 1] + data[at + 2] > 0;
    };
    return cells.filter(([dx, dy]) => {
      for (let y = -2; y <= 2; y++) for (let x = -2; x <= 2; x++) if (!lit(208 + dx + x, 208 + dy + y)) return false;
      return true;
    }).length;
  }, grid416.dots.filter(([, , ring, , t]) => ring === 0 && Math.abs(t - turn) < 0.01));
  const pick = (legend, label) => epix.$$eval("fieldset", (sets, legend, label) => {
    const set = sets.find((f) => f.querySelector("legend")?.textContent.trim().startsWith(legend));
    [...(set?.querySelectorAll("label") ?? [])].find((l) => l.textContent.trim() === label)?.click();
  }, legend, label);
  check("the Epix offers hour marks and a seconds dot",
    (await epix.content()).includes("Hour marks") && (await epix.content()).includes("Seconds dot"));
  check("…both off to start, so three o'clock has no mark", (await solidCellsNear(0.25)) === 0);
  await pick("Hour marks", "On");
  await new Promise((r) => setTimeout(r, 200));
  check("hour marks on puts them in the code", decoded(await epixCode()).timeHourMarks === 1, await epixCode());
  check("…and draws a solid mark at three o'clock", (await solidCellsNear(0.25)) === 1);
  await pick("Seconds dot", "On");
  await new Promise((r) => setTimeout(r, 200));
  check("the seconds dot goes in the code too",
    decoded(await epixCode()).timeSeconds === 1 && (await epixCode()).length === 48, await epixCode());
  check("…and is drawn at :42", (await solidCellsNear(42 / 60)) === 1);
  await epix.screenshot({ path: join(shots, "desktop-epix-time-extras.png") });
  await pick("Hour marks", "Off");
  await pick("Seconds dot", "Off");
  await epix.$$eval("label", (labels) => labels.find((l) => l.textContent.trim().startsWith("Instinct"))?.click());
  await new Promise((r) => setTimeout(r, 200));
  check("on the Crossover a stored time style shows as Off, as the watch reads it",
    (await epix.$eval(".rings .ring:nth-child(1) select", (el) => el.value)) === "8");
  check("…and four rings and four colours, with no centre ring",
    (await epix.$$(".rings .ring")).length === 4);
  check("…and no time ring extras, since it has no time ring",
    !(await epix.content()).includes("Hour marks"));
  await epixContext.close();

  // The 51mm has a fifth ring, its centre ball, and a fifth colour for it; both go in the
  // version-2 code, which every watch reads.
  const bigContext = await browser.createBrowserContext();
  const big = await bigContext.newPage();
  big.on("pageerror", (error) => errors.push(String(error)));
  await big.goto(`${origin}/#w=epix2pro51mm`, { waitUntil: "networkidle0" });
  const bigCode = () => big.$eval(".code output", (el) => el.textContent);
  const ringLabels = await big.$$eval(".rings .ring label", (labels) => labels.map((l) => l.textContent.trim()));
  check("the 51mm offers five rings, the last its centre ring",
    ringLabels.length === 5 && ringLabels[4] === "Centre ring", JSON.stringify(ringLabels));
  check("…which starts on Steps", decoded(await bigCode()).ring5 === 0, await bigCode());
  await big.select(".rings .ring:nth-child(5) select", "2");
  check("choosing the centre ring's source puts ring5 in the code", decoded(await bigCode()).ring5 === 2, await bigCode());
  check("…in a version-4 code", (await bigCode()).length === 48, await bigCode());
  await big.$$eval("label", (labels) => labels.find((l) => l.textContent.trim() === "Make your own")?.click());
  await new Promise((r) => setTimeout(r, 200));
  check("the colour builder has a fifth ring to colour on the 51mm", (await big.$$(".ring-tab")).length === 5);
  await big.$eval('label[for="colour-4"]', (label) => label.click());
  await typeHex(big, "#33aa66");
  check("…which reaches the code", decoded(await bigCode()).customColours[4] === 0x33aa66, await bigCode());
  await big.select("#stop-0", "4");
  check("…and can be a ramp stop", decoded(await bigCode()).customRamp[0] === 4, await bigCode());
  await big.screenshot({ path: join(shots, "desktop-51mm-five-rings.png") });
  await bigContext.close();

  const phone = await browser.newPage();
  await phone.setViewport({ width: 390, height: 844, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  await phone.goto(`${origin}/#c=${vector}&w=instinctcrossoveramoled`, { waitUntil: "networkidle0" });
  const width = await phone.evaluate(() => document.documentElement.scrollWidth);
  check("no sideways scroll at phone width", width <= 390, `${width}px`);
  const phoneDisc = await phone.$(".wheel-disc");
  check("the colour wheel shows at phone width", phoneDisc !== null);
  if (phoneDisc) {
    await phoneDisc.evaluate((el) => el.scrollIntoView({ block: "center" }));
    const fits = await phone.$eval(".wheel", (el) => el.getBoundingClientRect().right <= 390 - 16);
    check("…inside the page's margin", fits);
    const before = await phone.$eval(".hex", (el) => el.value);
    const box = await phoneDisc.boundingBox();
    await phone.touchscreen.tap(box.x + box.width * 0.2, box.y + box.height * 0.5);
    check("…and a tap on it picks a colour", (await phone.$eval(".hex", (el) => el.value)) !== before);
    await phone.screenshot({ path: join(shots, "phone-wheel.png") });
    await phone.evaluate(() => window.scrollTo(0, 0));
    await new Promise((r) => setTimeout(r, 300)); // the face grows back over a frame or two
  }
  const bar = await phone.$eval(".code", (el) => el.getBoundingClientRect().bottom);
  check("the code stays on screen at phone width", bar <= 844 + 1, `${bar}`);
  const meter = await phone.$eval(".meter", (el) => {
    const box = el.getBoundingClientRect();
    const stage = el.closest(".stage").getBoundingClientRect();
    return box.top >= stage.top && box.bottom <= stage.bottom;
  });
  check("the brightness meter sits under the face at phone width", meter);
  const faceBox = await phone.$eval("canvas.face", (el) => { const r = el.getBoundingClientRect(); return [r.left, r.right]; });
  check("the face fills the phone's width", faceBox[0] >= 15.5 && faceBox[1] <= 374.5 && faceBox[1] - faceBox[0] > 340, `${faceBox}`);
  await phone.screenshot({ path: join(shots, "phone-top.png") });
  await phone.screenshot({ path: join(shots, "phone-full.png"), fullPage: true });
  // Scrolled down to the controls, the face shrinks into a strip at the top and stays.
  const faceOnScreen = () => phone.$eval("canvas.face", (el) => {
    const r = el.getBoundingClientRect();
    return { top: r.top, bottom: r.bottom, size: r.width };
  });
  const fullFace = await faceOnScreen();
  await phone.$eval(".rings", (el) => el.scrollIntoView({ block: "center" }));
  await new Promise((r) => setTimeout(r, 150));
  const shrunk = await faceOnScreen();
  check("scrolled to the rings, the face stays on screen", shrunk.top >= 0 && shrunk.bottom <= 844, JSON.stringify(shrunk));
  check("…shrunk, but not too small to read", shrunk.size < fullFace.size * 0.5 && shrunk.size >= 100, `${shrunk.size} of ${fullFace.size}`);
  const ringClear = await phone.$eval(".rings .ring:nth-child(1) select", (el) => {
    const r = el.getBoundingClientRect();
    return document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2) === el;
  });
  check("…and the controls are not under it", ringClear);
  await phone.select(".rings .ring:nth-child(1) select", "7");
  await new Promise((r) => setTimeout(r, 150));
  check("a change made down there shows in the shrunk face", (await phone.$eval(".code output", (el) => el.textContent)) !== vector &&
    (await faceOnScreen()).top >= 0);
  await phone.screenshot({ path: join(shots, "phone-scrolled.png") });
  await phone.evaluate(() => window.scrollTo(0, 0));
  await new Promise((r) => setTimeout(r, 150));
  check("back at the top, the face is full size again", Math.abs((await faceOnScreen()).size - fullFace.size) < 1);
  check("the desktop face does not stick or shrink", await page.$eval(".stage", (el) => el.style.top === "") &&
    await page.$eval(".face-box", (el) => el.style.transform === ""));
  const savedFits = await phone.$$eval(".saved .entry", (rows) => rows.length > 0 && rows.every((row) => row.getBoundingClientRect().right <= 390 - 16 + 0.5));
  check("saved configs fit at phone width", savedFits);

  check("no console errors", errors.length === 0, errors.join(" | "));
} finally {
  await browser.close();
  server.kill();
}
console.log(failures ? `${failures} check(s) failed` : "all checks passed");
process.exit(failures ? 1 : 0);
