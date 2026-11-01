// End-to-end check of the built configurator in the machine's own Chrome.
//
// Every expected code is produced by the *Python* codec (tools/simctl/configcode.py),
// not by the page's own TypeScript, so a check that passes means two independent codecs
// agree on what the page produced. Run with `npm run e2e`; screenshots land in
// E2E_SHOTS (default: e2e/shots, gitignored).
import { execFileSync, spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
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
  await page.evaluateOnNewDocument(() => localStorage.clear());
  await page.goto(origin + "/", { waitUntil: "networkidle0" });

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
  await pickLabel("Awake");

  await pickLabel("Make your own");
  check("Make your own selects theme 99", (await code()) === python({ ...PAGE_START, theme: 99, ring2: 7 }), await code());
  const picker = await page.$("#colour-1");
  await page.$eval("#colour-1", (input) => {
    input.value = "#050505";
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  const colours = [0xe879f9, 0x050505, 0x7fd4ff, 0xff6b5b];
  check("a picked colour reaches the code",
    (await code()) === python({ ...PAGE_START, theme: 99, ring2: 7, customColours: colours }), await code());
  const warnings = await page.$$eval(".warnings p", (ps) => ps.map((p) => p.textContent));
  check("a too-dark colour is warned about", warnings.some((text) => text.includes("ring 2 is very dark")), warnings.join(" | "));
  check("the colour picker is not rebuilt under the cursor", await picker.evaluate((el) => el.isConnected));
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

  await page.click(".actions .primary");
  await new Promise((r) => setTimeout(r, 200));
  check("Copy code puts the code on the clipboard",
    (await page.evaluate(() => navigator.clipboard.readText())) === (await code()));

  const vector = "AWMCAQEAAgkKDQcARv___wAAABI0VqvN7wcDSQ";
  const buttons = await page.$$(".actions .quiet");
  await buttons[1].click();
  await page.type("#paste", "AWMCAQEAAgkKDQcARv///wAAABI0VqvN7wcDSQ==");
  await page.click(".paste button");
  check("a pasted code loads, spelled either way", (await code()) === vector, await code());
  check("…and closes the paste box", (await page.$("#paste")) === null);

  const before = await code();
  await (await page.$$(".actions .quiet"))[1].click();
  await page.type("#paste", vector.slice(0, -1) + "x");
  await page.click(".paste button");
  const error = await page.$eval(".error", (el) => el.textContent).catch(() => "");
  check("a damaged code is refused with a reason", error.includes("checksum"), error);
  check("…and changes nothing", (await code()) === before);

  await page.goto(`${origin}/#c=${vector}&w=epix2pro51mm`, { waitUntil: "networkidle0" });
  await page.reload({ waitUntil: "networkidle0" });
  check("a link opens on its code", (await code()) === vector);
  check("…and its watch", (await page.$eval("canvas.face", (c) => c.width % 454 === 0)));
  check("…with the drawn-hands labels", (await page.content()).includes("White and grey"));

  const phone = await browser.newPage();
  await phone.setViewport({ width: 390, height: 844, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  await phone.goto(`${origin}/#c=${vector}&w=instinctcrossoveramoled`, { waitUntil: "networkidle0" });
  const width = await phone.evaluate(() => document.documentElement.scrollWidth);
  check("no sideways scroll at phone width", width <= 390, `${width}px`);
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

  check("no console errors", errors.length === 0, errors.join(" | "));
} finally {
  await browser.close();
  server.kill();
}
console.log(failures ? `${failures} check(s) failed` : "all checks passed");
process.exit(failures ? 1 : 0);
