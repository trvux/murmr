"use client";

import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { useEffect, useState } from "react";
import { cn } from "@/lib/utils";
import type { Dictionary } from "@/dictionaries";

/** The same sentence before and after the cleanup step. It flips by itself until the person takes over. */
export function CleanupDemo({ t }: { t: Dictionary["cleanup"] }) {
  const reduce = useReducedMotion();
  const [index, setIndex] = useState(0);
  const [clean, setClean] = useState(false);
  const [manual, setManual] = useState(false);
  const example = t.examples[index];

  useEffect(() => {
    if (manual || reduce) return;
    const id = setInterval(() => setClean((c) => !c), 3200);
    return () => clearInterval(id);
  }, [manual, reduce]);

  const take = (fn: () => void) => {
    setManual(true);
    fn();
  };

  return (
    <div className="grid gap-8 lg:grid-cols-[0.8fr_1.2fr] lg:items-center">
      <div className="space-y-2" role="tablist" aria-label={t.title}>
        {t.examples.map((e, i) => (
          <button
            key={e.tag}
            type="button"
            role="tab"
            aria-selected={i === index}
            onClick={() => take(() => setIndex(i))}
            className={cn("block w-full rounded-xl border px-4 py-3 text-left text-sm transition-colors", i === index ? "border-foreground/40 bg-card font-medium" : "border-border text-muted-foreground hover:bg-card/60")}
          >
            {e.tag}
          </button>
        ))}
        <p className="pt-3 text-sm leading-relaxed text-muted-foreground">{t.note}</p>
      </div>

      <div className="rounded-2xl border border-border bg-card p-6 md:p-8">
        <div className="mb-5 flex items-center justify-between">
          <p className="font-mono text-xs uppercase tracking-[0.16em] text-muted-foreground">{clean ? t.cleanLabel : t.rawLabel}</p>
          <div className="flex rounded-lg border border-border p-0.5 text-xs" role="group">
            {[false, true].map((value) => (
              <button
                key={String(value)}
                type="button"
                aria-pressed={clean === value}
                onClick={() => take(() => setClean(value))}
                className={cn("rounded-md px-3 py-1.5 transition-colors", clean === value ? "bg-foreground text-background" : "text-muted-foreground hover:text-foreground")}
              >
                {value ? t.toggleClean : t.toggleRaw}
              </button>
            ))}
          </div>
        </div>
        <div className="min-h-[7.5rem]" aria-live="polite">
          <AnimatePresence mode="wait">
            <motion.p
              key={`${index}-${clean}`}
              className={cn("text-xl leading-relaxed md:text-2xl", clean ? "font-display text-foreground" : "font-mono text-base text-muted-foreground md:text-lg")}
              initial={reduce ? false : { opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={reduce ? undefined : { opacity: 0, y: -8 }}
              transition={{ duration: 0.28 }}
            >
              {clean ? example.clean : example.raw}
            </motion.p>
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}
