import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

export function Section({ id, eyebrow, title, intro, children, className }: { id?: string; eyebrow: string; title: string; intro?: string; children: ReactNode; className?: string }) {
  return (
    <section id={id} className={cn("scroll-mt-20 py-20 md:py-28", className)}>
      <div className="mx-auto max-w-6xl px-5 md:px-8">
        <p className="font-mono text-xs uppercase tracking-[0.18em] text-signal">{eyebrow}</p>
        <h2 className="mt-3 max-w-3xl font-display text-4xl leading-[1.08] tracking-tight md:text-5xl">{title}</h2>
        {intro ? <p className="mt-5 max-w-2xl text-lg leading-relaxed text-muted-foreground">{intro}</p> : null}
        <div className="mt-12">{children}</div>
      </div>
    </section>
  );
}
