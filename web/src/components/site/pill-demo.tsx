"use client";

import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { useCallback, useEffect, useRef, useState } from "react";
import { RotateCcw } from "lucide-react";
import { Wave } from "./wave";

type Phase = "idle" | "listening" | "transcribing" | "typing" | "done";

interface Props {
  labels: { hold: string; listening: string; transcribing: string; sentence: string; fieldLabel: string; replay: string };
}

const wait = (ms: number, signal: { cancelled: boolean }) =>
  new Promise<void>((resolve) => setTimeout(() => resolve(), signal.cancelled ? 0 : ms));

/** The product in one loop: hold a key, the pill grows out of the notch and listens, then the words appear in a text field. */
export function PillDemo({ labels }: Props) {
  const reduce = useReducedMotion();
  const [phase, setPhase] = useState<Phase>("done");
  const [typed, setTyped] = useState(labels.sentence);
  const [run, setRun] = useState(0);
  const token = useRef({ cancelled: false });

  const play = useCallback(async () => {
    token.current.cancelled = true;
    const mine = { cancelled: false };
    token.current = mine;
    await wait(0, mine); // state is set after this first tick, never synchronously inside the effect that starts the loop
    if (mine.cancelled) return;
    setTyped("");
    setPhase("idle");
    await wait(700, mine);
    if (mine.cancelled) return;
    setPhase("listening");
    await wait(2800, mine);
    if (mine.cancelled) return;
    setPhase("transcribing");
    await wait(1100, mine);
    if (mine.cancelled) return;
    setPhase("typing");
    for (let i = 1; i <= labels.sentence.length; i++) {
      if (mine.cancelled) return;
      setTyped(labels.sentence.slice(0, i));
      await wait(22, mine);
    }
    setPhase("done");
    await wait(4200, mine);
    if (!mine.cancelled) setRun((n) => n + 1);
  }, [labels.sentence]);

  useEffect(() => {
    if (reduce) return; // the finished state is already showing: that is how it starts
    const start = setTimeout(() => void play(), 0); // from a timer, not the effect body: the loop then drives the state
    const current = token;
    return () => {
      clearTimeout(start);
      current.current.cancelled = true;
    };
  }, [play, run, reduce, labels.sentence]);

  const listening = phase === "listening";
  const working = phase === "transcribing";
  const expanded = listening || working;
  const status = listening ? labels.listening : working ? labels.transcribing : "";

  return (
    <div className="relative mx-auto w-full max-w-xl">
      <div className="overflow-hidden rounded-2xl border border-border bg-card shadow-[0_30px_80px_-40px_rgb(29_26_21/0.45)]">
        {/* the Mac's top edge with the notch, and the pill that grows out of it */}
        <div className="relative h-[132px] bg-secondary">
          <div className="absolute inset-x-0 top-0 flex h-7 items-center gap-1.5 px-4">
            <span className="size-2.5 rounded-full bg-foreground/15" />
            <span className="size-2.5 rounded-full bg-foreground/15" />
            <span className="size-2.5 rounded-full bg-foreground/15" />
          </div>
          <motion.div
            className="absolute left-1/2 top-0 -translate-x-1/2 overflow-hidden rounded-b-[22px] bg-black text-white"
            animate={{ width: expanded ? 300 : 132, height: expanded ? 98 : 26 }}
            transition={{ type: "spring", stiffness: 260, damping: 28 }}
          >
            <AnimatePresence mode="wait">
              {expanded ? (
                <motion.div key="open" className="flex h-full flex-col justify-end px-5 pb-3" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.2 }}>
                  <div className="flex items-center justify-between pb-1 text-[11px] text-white/60">
                    <span className="flex items-center gap-1.5">
                      <span className="size-1.5 rounded-full bg-[#e0825c]" />
                      {status}
                    </span>
                    <span className="font-mono">⌥</span>
                  </div>
                  {listening ? (
                    <Wave active className="h-10 w-full" />
                  ) : (
                    <div className="flex h-10 items-center justify-center gap-2 text-sm text-white/85">
                      <motion.span className="size-4 rounded-full border-2 border-white/80 border-t-transparent" animate={{ rotate: 360 }} transition={{ repeat: Infinity, duration: 0.9, ease: "linear" }} />
                      {labels.transcribing}…
                    </div>
                  )}
                </motion.div>
              ) : null}
            </AnimatePresence>
          </motion.div>
        </div>
        {/* any text field in any app */}
        <div className="space-y-3 p-5">
          <p className="font-mono text-[11px] uppercase tracking-[0.16em] text-muted-foreground">{labels.fieldLabel}</p>
          <div className="min-h-[92px] rounded-xl border border-border bg-background p-4 text-[17px] leading-relaxed" aria-live="polite">
            {typed}
            <span className={`ml-0.5 inline-block h-[1.1em] w-[2px] translate-y-[3px] bg-signal ${phase === "typing" || phase === "done" ? "animate-pulse" : "opacity-0"}`} />
          </div>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <kbd className={`rounded-md border px-2 py-1 font-mono text-xs transition-colors ${listening ? "border-signal bg-signal/10 text-signal" : "border-border bg-card"}`}>⌥</kbd>
              <span>{labels.hold}</span>
            </div>
            {!reduce ? (
              <button type="button" onClick={() => setRun((n) => n + 1)} className="inline-flex items-center gap-1.5 rounded-md px-2 py-1 text-xs text-muted-foreground transition-colors hover:text-foreground">
                <RotateCcw className="size-3.5" aria-hidden="true" />
                {labels.replay}
              </button>
            ) : null}
          </div>
        </div>
      </div>
    </div>
  );
}
