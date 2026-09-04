"use client";

import { useEffect, useRef } from "react";
import type { Mode } from "./palette-data";

type Props = {
  colors: string[];
  ramp: number[];
  mode: Mode;
  label: string;
  compact?: boolean;
};

const TAU = Math.PI * 2;
const LEVELS = [0.84, 0.67, 0.49, 0.32];

function hexToRgb(hex: string) {
  const value = Number.parseInt(hex.slice(1), 16);
  return [(value >> 16) & 255, (value >> 8) & 255, value & 255];
}

function rgbToHex(rgb: number[]) {
  return `#${rgb.map((channel) => Math.round(channel).toString(16).padStart(2, "0")).join("")}`;
}

function mix(from: string, to: string, amount: number) {
  const a = hexToRgb(from);
  const b = hexToRgb(to);
  return rgbToHex(a.map((channel, index) => channel + (b[index] - channel) * amount));
}

function rampColor(colors: string[], ramp: number[], fraction: number) {
  const cold = colors[ramp[0]];
  const middle = colors[ramp[1]];
  const hot = colors[ramp[2]];
  return fraction <= 0.5
    ? mix(cold, middle, fraction * 2)
    : mix(middle, hot, (fraction - 0.5) * 2);
}

export function WatchDial({ colors, ramp, mode, label, compact = false }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const size = compact ? 260 : 520;
    const ratio = window.devicePixelRatio || 1;
    canvas.width = size * ratio;
    canvas.height = size * ratio;
    const context = canvas.getContext("2d");
    if (!context) return;
    context.scale(ratio, ratio);

    const centre = size / 2;
    const radius = size * 0.42;
    const hub = size * 0.07;
    const thickness = (radius - hub) / 4;
    const pitch = compact ? 6.2 : 10.2;
    const arm = compact ? 1.45 : 2.25;

    context.clearRect(0, 0, size, size);
    const halo = context.createRadialGradient(centre, centre, hub, centre, centre, radius * 1.2);
    halo.addColorStop(0, "#17191b");
    halo.addColorStop(0.72, "#080909");
    halo.addColorStop(1, "#020303");
    context.fillStyle = halo;
    context.beginPath();
    context.arc(centre, centre, radius * 1.16, 0, TAU);
    context.fill();

    for (let y = -radius; y <= radius; y += pitch) {
      for (let x = -radius; x <= radius; x += pitch) {
        const distance = Math.hypot(x, y);
        if (distance > radius || distance < hub) continue;
        const ring = Math.min(3, Math.floor((radius - distance) / thickness));
        const angle = (Math.atan2(x, -y) + TAU) % TAU;
        const fraction = angle / TAU;
        const base = mode === "temperature" && ring === 0
          ? rampColor(colors, ramp, fraction)
          : colors[ring];
        const filled = mode === "temperature" && ring === 0
          ? fraction >= 0.08 && fraction <= 0.78
          : fraction <= LEVELS[ring];
        const weak = mode === "always-on" ? 0.43 : 0.54;
        const color = filled ? base : mix("#000000", base, weak);

        context.strokeStyle = color;
        context.globalAlpha = filled ? 1 : 0.72;
        context.lineWidth = compact ? 0.8 : 1.15;
        context.beginPath();
        context.moveTo(centre + x - arm, centre + y);
        context.lineTo(centre + x + arm, centre + y);
        context.moveTo(centre + x, centre + y - arm);
        context.lineTo(centre + x, centre + y + arm);
        context.stroke();
      }
    }

    context.globalAlpha = 1;
    context.strokeStyle = "rgba(255,255,255,.12)";
    context.lineWidth = 1;
    context.beginPath();
    context.arc(centre, centre, radius * 1.055, 0, TAU);
    context.stroke();
  }, [colors, ramp, mode, compact]);

  return (
    <canvas
      ref={canvasRef}
      className={compact ? "watch-canvas watch-canvas--compact" : "watch-canvas"}
      aria-label={`${label} palette in ${mode} mode`}
      role="img"
    />
  );
}
