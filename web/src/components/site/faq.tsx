"use client";

import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import type { Dictionary } from "@/dictionaries";

export function Faq({ t }: { t: Dictionary["faq"] }) {
  return (
    <Accordion className="max-w-3xl divide-y divide-border border-y border-border">
      {t.items.map((item, i) => (
        <AccordionItem key={i} value={String(i)} className="border-0">
          <AccordionTrigger className="py-5 text-left font-display text-xl font-medium hover:no-underline">{item.q}</AccordionTrigger>
          <AccordionContent className="pb-5 text-base leading-relaxed text-muted-foreground">{item.a}</AccordionContent>
        </AccordionItem>
      ))}
    </Accordion>
  );
}
