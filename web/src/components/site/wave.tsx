"use client";

import { useEffect, useRef } from "react";

/** The Murmr wave: several thin lines that weave and follow a made-up voice level. Draws nothing when `active` is false. */
export function Wave({ active, className }: { active: boolean; className?: string }) {
  const canvas = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const el = canvas.current;
    if (!el) return;
    const ctx = el.getContext("2d");
    if (!ctx) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const resize = () => {
      el.width = el.clientWidth * dpr;
      el.height = el.clientHeight * dpr;
    };
    resize();
    const signal = getComputedStyle(document.documentElement).getPropertyValue("--signal").trim() || "#b5532f";
    const layers = [
      { freq: 9, speed: 2.1, phase: 0, alpha: 1, width: 2.2, amp: 1 },
      { freq: 13, speed: -1.6, phase: 1.3, alpha: 0.7, width: 1.6, amp: 0.8 },
      { freq: 7, speed: 1.2, phase: 2.4, alpha: 0.5, width: 1.2, amp: 0.65 },
      { freq: 17, speed: -2.4, phase: 0.7, alpha: 0.4, width: 1, amp: 0.5 },
      { freq: 11, speed: 1.9, phase: 3.1, alpha: 0.3, width: 0.9, amp: 0.4 },
    ];
    let raf = 0;
    const started = performance.now();
    const draw = (now: number) => {
      const t = (now - started) / 1000;
      const w = el.width;
      const h = el.height;
      ctx.clearRect(0, 0, w, h);
      // a gently breathing voice level, never silent while active
      const level = active ? 0.45 + 0.4 * Math.abs(Math.sin(t * 1.7) * Math.sin(t * 0.55 + 1)) : 0.04;
      ctx.lineCap = "round";
      for (const l of layers) {
        ctx.beginPath();
        for (let x = 0; x <= w; x += 3) {
          const u = x / w;
          const envelope = Math.pow(Math.sin(Math.PI * u), 1.4);
          const y = h / 2 + Math.sin(u * l.freq + t * l.speed + l.phase) * (h / 2 - 2) * level * l.amp * envelope;
          if (x === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }
        ctx.strokeStyle = signal;
        ctx.globalAlpha = l.alpha * (active ? 1 : 0.35);
        ctx.lineWidth = l.width * dpr;
        ctx.stroke();
      }
      ctx.globalAlpha = 1;
      if (!reduce) raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);
    window.addEventListener("resize", resize);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", resize);
    };
  }, [active]);

  return <canvas ref={canvas} className={className} aria-hidden="true" />;
}
