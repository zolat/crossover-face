"use client";

import { useMemo, useState } from "react";
import { CANDIDATE_KEYS, Mode, PALETTE_KEYS, PALETTES, PaletteKey, RING_NAMES } from "./palette-data";
import { WatchDial } from "./watch-dial";

type PaletteState = Record<PaletteKey, { colors: string[]; ramp: number[] }>;

function initialState(): PaletteState {
  return Object.fromEntries(
    PALETTE_KEYS.map((key) => [key, {
      colors: [...PALETTES[key].colors],
      ramp: [...PALETTES[key].ramp],
    }]),
  ) as PaletteState;
}

function linearChannel(value: number) {
  const normalized = value / 255;
  return normalized <= 0.04045
    ? normalized / 12.92
    : ((normalized + 0.055) / 1.055) ** 2.4;
}

function relativeLuminance(hex: string) {
  const value = Number.parseInt(hex.slice(1), 16);
  const red = linearChannel((value >> 16) & 255);
  const green = linearChannel((value >> 8) & 255);
  const blue = linearChannel(value & 255);
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

function lab(hex: string) {
  const value = Number.parseInt(hex.slice(1), 16);
  const red = linearChannel((value >> 16) & 255);
  const green = linearChannel((value >> 8) & 255);
  const blue = linearChannel(value & 255);
  const x = (red * 0.4124 + green * 0.3576 + blue * 0.1805) / 0.95047;
  const y = red * 0.2126 + green * 0.7152 + blue * 0.0722;
  const z = (red * 0.0193 + green * 0.1192 + blue * 0.9505) / 1.08883;
  const convert = (channel: number) => channel > 0.008856
    ? Math.cbrt(channel)
    : 7.787 * channel + 16 / 116;
  const fx = convert(x);
  const fy = convert(y);
  const fz = convert(z);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}

function deltaE(first: string, second: string) {
  const a = lab(first);
  const b = lab(second);
  return Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
}

function isHex(value: string) {
  return /^#[0-9a-f]{6}$/i.test(value);
}

export default function Home() {
  const [selected, setSelected] = useState<PaletteKey>("arcade");
  const [mode, setMode] = useState<Mode>("awake");
  const [palettes, setPalettes] = useState<PaletteState>(initialState);
  const [copied, setCopied] = useState(false);
  const current = palettes[selected];
  const definition = PALETTES[selected];

  const metrics = useMemo(() => {
    const adjacent = current.colors.slice(0, 3).map((color, index) =>
      deltaE(color, current.colors[index + 1]),
    );
    const weights = [0.392, 0.306, 0.22, 0.082];
    const luminance = current.colors.reduce(
      (total, color, index) => total + relativeLuminance(color) * weights[index],
      0,
    );
    return { minimumDistance: Math.min(...adjacent), luminance };
  }, [current]);

  function updateColor(index: number, value: string) {
    if (!isHex(value)) return;
    setPalettes((existing) => ({
      ...existing,
      [selected]: {
        ...existing[selected],
        colors: existing[selected].colors.map((color, colorIndex) =>
          colorIndex === index ? value.toUpperCase() : color,
        ),
      },
    }));
  }

  function updateRamp(position: number, value: number) {
    setPalettes((existing) => ({
      ...existing,
      [selected]: {
        ...existing[selected],
        ramp: existing[selected].ramp.map((stop, stopIndex) =>
          stopIndex === position ? value : stop,
        ),
      },
    }));
  }

  function moveColor(index: number, direction: -1 | 1) {
    const destination = index + direction;
    if (destination < 0 || destination > 3) return;
    setPalettes((existing) => {
      const colors = [...existing[selected].colors];
      [colors[index], colors[destination]] = [colors[destination], colors[index]];
      const ramp = existing[selected].ramp.map((stop) => {
        if (stop === index) return destination;
        if (stop === destination) return index;
        return stop;
      });
      return { ...existing, [selected]: { colors, ramp } };
    });
  }

  function resetPalette() {
    setPalettes((existing) => ({
      ...existing,
      [selected]: { colors: [...definition.colors], ramp: [...definition.ramp] },
    }));
  }

  async function copyPalette() {
    const text = `${definition.name}: ${current.colors.join(" → ")}\nRamp: ${current.ramp.map((index) => current.colors[index]).join(" → ")}`;
    await navigator.clipboard.writeText(text);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1600);
  }

  return (
    <main>
      <header className="topbar">
        <div className="brand-lockup">
          <span className="brand-mark" aria-hidden="true">✣</span>
          <div>
            <p className="eyebrow">Crossover Face / Design tool</p>
            <h1>Colour Field Lab</h1>
          </div>
        </div>
        <div className="prototype-note">
          <span className="status-dot" />
          Prototype only — watch settings stay unchanged
        </div>
      </header>

      <section className="workspace" aria-label="Palette editor">
        <aside className="palette-rail">
          <div className="section-heading">
            <p className="eyebrow">Palette</p>
            <span>04 options</span>
          </div>
          <div className="palette-list">
            {PALETTE_KEYS.map((key) => {
              const palette = PALETTES[key];
              return (
                <button
                  key={key}
                  className={`palette-option ${selected === key ? "is-selected" : ""}`}
                  onClick={() => setSelected(key)}
                  aria-pressed={selected === key}
                >
                  <span className="palette-option__copy">
                    <strong>{palette.name}</strong>
                    <small>{palette.status}</small>
                  </span>
                  <span className="mini-swatches" aria-hidden="true">
                    {palettes[key].colors.map((color, index) => (
                      <i key={`${color}-${index}`} style={{ background: color }} />
                    ))}
                  </span>
                </button>
              );
            })}
          </div>
          <div className="rail-note">
            <span>Tip</span>
            Judge neighbours first. Adjacent rings are the pairs most likely to blur together.
          </div>
        </aside>

        <section className="preview-panel">
          <div className="preview-toolbar">
            <div>
              <p className="eyebrow">Live preview</p>
              <h2>{definition.name}</h2>
            </div>
            <div className="mode-switch" role="group" aria-label="Preview mode">
              {(["awake", "always-on", "temperature"] as Mode[]).map((item) => (
                <button
                  key={item}
                  onClick={() => setMode(item)}
                  className={mode === item ? "is-active" : ""}
                  aria-pressed={mode === item}
                >
                  {item === "always-on" ? "Always-on" : item[0].toUpperCase() + item.slice(1)}
                </button>
              ))}
            </div>
          </div>
          <div className="watch-stage">
            <div className="watch-case">
              <span className="watch-case__tick watch-case__tick--top" />
              <span className="watch-case__tick watch-case__tick--right" />
              <span className="watch-case__tick watch-case__tick--bottom" />
              <span className="watch-case__tick watch-case__tick--left" />
              <WatchDial colors={current.colors} ramp={current.ramp} mode={mode} label={definition.name} />
            </div>
            <div className="preview-caption">
              <span>{mode === "temperature" ? "Outer ring / temperature range" : "Sample activity levels"}</span>
              <span>Instinct Crossover AMOLED · 390 px</span>
            </div>
          </div>
        </section>

        <aside className="controls-panel">
          <div className="controls-intro">
            <div>
              <p className="eyebrow">Tune</p>
              <h2>Ring colours</h2>
            </div>
            <span className={`status-pill ${definition.status === "Shipping" ? "status-pill--shipping" : ""}`}>
              {definition.status}
            </span>
          </div>
          <p className="palette-description">{definition.description}</p>

          <div className="color-stack">
            {current.colors.map((color, index) => (
              <div className="color-row" key={`${selected}-${index}`}>
                <label className="color-control">
                  <input
                    type="color"
                    value={color}
                    onChange={(event) => updateColor(index, event.target.value)}
                    aria-label={`${RING_NAMES[index]} ring colour`}
                  />
                  <span>
                    <small>{RING_NAMES[index]} ring</small>
                    <strong>{color}</strong>
                  </span>
                </label>
                <div className="reorder-buttons" aria-label={`Reorder ${RING_NAMES[index]} colour`}>
                  <button onClick={() => moveColor(index, -1)} disabled={index === 0} aria-label="Move outward">↑</button>
                  <button onClick={() => moveColor(index, 1)} disabled={index === 3} aria-label="Move inward">↓</button>
                </div>
              </div>
            ))}
          </div>

          <div className="ramp-editor">
            <div>
              <p className="eyebrow">Temperature ramp</p>
              <span>Cold → middle → hot</span>
            </div>
            <div className="ramp-selects">
              {["Cold", "Mid", "Hot"].map((label, position) => (
                <label key={label}>
                  <span>{label}</span>
                  <select
                    value={current.ramp[position]}
                    onChange={(event) => updateRamp(position, Number(event.target.value))}
                  >
                    {current.colors.map((color, index) => (
                      <option key={`${color}-${index}`} value={index}>{RING_NAMES[index]} · {color}</option>
                    ))}
                  </select>
                </label>
              ))}
            </div>
            <div className="ramp-strip" aria-label="Temperature ramp preview">
              <i style={{ background: current.colors[current.ramp[0]] }} />
              <i style={{ background: current.colors[current.ramp[1]] }} />
              <i style={{ background: current.colors[current.ramp[2]] }} />
            </div>
          </div>

          <div className="metrics">
            <div>
              <span>Closest neighbours</span>
              <strong>ΔE {metrics.minimumDistance.toFixed(0)}</strong>
              <small>{metrics.minimumDistance >= 50 ? "Strong separation" : "Review at 1:1"}</small>
            </div>
            <div>
              <span>Weighted brightness</span>
              <strong>{(metrics.luminance * 100).toFixed(1)}%</strong>
              <small>Relative palette signal</small>
            </div>
          </div>

          <div className="control-actions">
            <button className="button button--secondary" onClick={resetPalette}>Reset</button>
            <button className="button button--primary" onClick={copyPalette}>{copied ? "Copied" : "Copy palette"}</button>
          </div>
        </aside>
      </section>

      <section className="comparison-section">
        <div className="comparison-heading">
          <div>
            <p className="eyebrow">Candidate board</p>
            <h2>Compare the field, not the hex</h2>
          </div>
          <p>Arcade remains the one mockup-only palette. Click it to move it into the editor.</p>
        </div>
        <div className="candidate-grid">
          {CANDIDATE_KEYS.map((key) => (
            <button
              className={`candidate-card ${selected === key ? "is-selected" : ""}`}
              key={key}
              onClick={() => setSelected(key)}
            >
              <WatchDial colors={palettes[key].colors} ramp={palettes[key].ramp} mode={mode} label={PALETTES[key].name} compact />
              <span className="candidate-card__body">
                <span>
                  <strong>{PALETTES[key].name}</strong>
                  <small>{PALETTES[key].description}</small>
                </span>
                <span className="candidate-arrow" aria-hidden="true">↗</span>
              </span>
            </button>
          ))}
        </div>
      </section>
    </main>
  );
}
