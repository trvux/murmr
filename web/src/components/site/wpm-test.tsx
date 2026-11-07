"use client";

import { animate, motion, useReducedMotion } from "motion/react";
import { useEffect, useMemo, useRef, useState } from "react";
import { cn } from "@/lib/utils";
import type { Dictionary } from "@/dictionaries";

const SPEAKING_WPM = 150;

/** A typing test. WPM is the standard measure (five characters count as one word), so it means the same in any language. */
export function WpmTest({ t }: { t: Dictionary["wpm"] }) {
  const reduce = useReducedMotion();
  const target = t.sentence;
  const [text, setText] = useState("");
  const [result, setResult] = useState<{ wpm: number; accuracy: number } | null>(null);
  const [tooFast, setTooFast] = useState(false);
  const [started, setStarted] = useState(false);
  const [words, setWords] = useState(2000);
  const [elapsed, setElapsed] = useState(0);
  const startedAt = useRef<number | null>(null);
  const field = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (!started || result) return;
    const id = setInterval(() => setElapsed((performance.now() - (startedAt.current ?? 0)) / 1000), 200);
    return () => clearInterval(id);
  }, [started, result]);

  const chars = useMemo(() => Array.from(target), [target]);

  function onChange(value: string) {
    if (result) return;
    if (tooFast) setTooFast(false);
    if (startedAt.current === null && value.length > 0) {
      startedAt.current = performance.now();
      setStarted(true);
    }
    const typed = Array.from(value).slice(0, chars.length);
    setText(typed.join(""));
    if (typed.length >= chars.length && startedAt.current !== null) {
      const minutes = Math.max((performance.now() - startedAt.current) / 60000, 1 / 600);
      const correct = typed.filter((c, i) => c === chars[i]).length;
      const wpm = Math.max(1, Math.round(correct / 5 / minutes));
      // the fastest competitive typists stay under about 250; anything above that was not typed by hand
      if (wpm > 260) {
        setTooFast(true);
        setText("");
        startedAt.current = null;
        setStarted(false);
        setElapsed(0);
        return;
      }
      setResult({ wpm, accuracy: Math.round((correct / chars.length) * 100) });
    }
  }

  function reset() {
    setText("");
    setResult(null);
    setElapsed(0);
    startedAt.current = null;
    setStarted(false);
    field.current?.focus();
  }

  const typed = Array.from(text);
  const ratio = result ? SPEAKING_WPM / result.wpm : 0;
  const saved = result ? Math.max(0, Math.round(words / result.wpm - words / SPEAKING_WPM)) : 0;

  return (
    <div className="grid gap-10 lg:grid-cols-[1.1fr_0.9fr] lg:items-start">
      <div className="rounded-2xl border border-border bg-card p-6 md:p-8">
        <p className="font-mono text-xs uppercase tracking-[0.16em] text-muted-foreground">{t.prompt}</p>
        <p className="mt-4 font-display text-[1.35rem] leading-[1.6] md:text-2xl" aria-hidden="true">
          {chars.map((c, i) => {
            const done = i < typed.length;
            const ok = done && typed[i] === c;
            return (
              <span key={i} className={cn(!done && "text-muted-foreground/70", ok && "text-foreground", done && !ok && "text-signal underline decoration-signal/60 underline-offset-4", i === typed.length && !result && "rounded-sm bg-signal/15")}>
                {c}
              </span>
            );
          })}
        </p>
        <textarea
          ref={field}
          value={text}
          onChange={(e) => onChange(e.target.value)}
          onPaste={(e) => e.preventDefault()}
          readOnly={!!result}
          rows={3}
          spellCheck={false}
          autoCorrect="off"
          autoCapitalize="off"
          aria-label={t.prompt}
          placeholder={t.placeholder}
          className="mt-6 w-full resize-none rounded-xl border border-input bg-background p-4 text-lg outline-none transition-shadow placeholder:text-muted-foreground/70 focus-visible:ring-3 focus-visible:ring-ring/40"
        />
        <div className="mt-3 flex items-center justify-between text-sm text-muted-foreground">
          <span>{!started ? t.start : `${elapsed.toFixed(1)} s`}</span>
          {result ? (
            <button type="button" onClick={reset} className="font-medium text-foreground underline underline-offset-4 hover:text-signal">
              {t.again}
            </button>
          ) : null}
        </div>
      </div>

      <div className="min-h-[320px] rounded-2xl border border-border bg-secondary/60 p-6 md:p-8" aria-live="polite">
        {result ? (
          <div className="space-y-7">
            <Bar label={t.typing} value={result.wpm} max={Math.max(result.wpm, SPEAKING_WPM)} unit={t.wpm} tone="ink" animateIn={!reduce} />
            <Bar label={t.speaking} value={SPEAKING_WPM} max={Math.max(result.wpm, SPEAKING_WPM)} unit={t.wpm} tone="signal" animateIn={!reduce} />
            <p className="text-sm text-muted-foreground">
              {t.accuracy}: <strong className="text-foreground">{result.accuracy}%</strong>
            </p>
            <p className="font-display text-2xl leading-snug">{t.faster.replace("{x}", ratio.toFixed(1))}</p>
            <div className="space-y-3 rounded-xl border border-border bg-card p-4">
              <label className="flex items-center justify-between gap-4 text-sm text-muted-foreground" htmlFor="words-per-day">
                {t.wordsPerDay}
                <span className="font-mono text-foreground">{words.toLocaleString()}</span>
              </label>
              <input id="words-per-day" type="range" min={500} max={8000} step={250} value={words} onChange={(e) => setWords(Number(e.target.value))} className="w-full accent-[var(--signal)]" />
              <p className="text-lg">
                <strong className="font-display text-2xl">{t.saved.replace("{m}", String(saved))}</strong>
                <span className="ml-2 text-sm text-muted-foreground">{t.savedNote.replace("{w}", words.toLocaleString())}</span>
              </p>
            </div>
          </div>
        ) : (
          <div className="flex h-full min-h-[270px] flex-col justify-center">
            <p className="font-display text-3xl leading-tight md:text-4xl">{t.title}</p>
            <p className="mt-4 text-muted-foreground">{tooFast ? t.tooFast : t.intro}</p>
          </div>
        )}
        <p className="mt-6 border-t border-border pt-4 text-xs leading-relaxed text-muted-foreground">
          {t.disclaimer}{" "}
          <a href={t.sourceUrl} className="underline underline-offset-4 hover:text-foreground" target="_blank" rel="noopener noreferrer">
            {t.sourceLabel}
          </a>
          : {t.sourceText}
        </p>
      </div>
    </div>
  );
}

function Bar({ label, value, max, unit, tone, animateIn }: { label: string; value: number; max: number; unit: string; tone: "ink" | "signal"; animateIn: boolean }) {
  const [shown, setShown] = useState(animateIn ? 0 : value);
  useEffect(() => {
    if (!animateIn) return;
    const controls = animate(0, value, { duration: 0.9, ease: [0.22, 1, 0.36, 1], onUpdate: setShown });
    return () => controls.stop();
  }, [value, animateIn]);
  return (
    <div>
      <div className="mb-2 flex items-baseline justify-between">
        <span className="text-sm text-muted-foreground">{label}</span>
        <span className="font-display text-3xl">
          {Math.round(shown)} <span className="font-sans text-sm text-muted-foreground">{unit}</span>
        </span>
      </div>
      <div className="h-3 overflow-hidden rounded-full bg-border">
        <motion.div className={cn("h-full rounded-full", tone === "signal" ? "bg-signal" : "bg-foreground")} animate={{ width: `${(shown / max) * 100}%` }} transition={{ duration: 0.05 }} />
      </div>
    </div>
  );
}
