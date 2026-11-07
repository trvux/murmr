"use client";

import { localeNames, localePath, locales, type Locale } from "@/lib/i18n";
import { cn } from "@/lib/utils";

/** Two plain links. Choosing one is remembered (a cookie), so the first-visit suggestion never fights the person. */
export function LanguageSwitch({ locale, label }: { locale: Locale; label: string }) {
  return (
    <nav aria-label={label} className="flex items-center gap-1 text-sm">
      {locales.map((l) => (
        <a
          key={l}
          href={localePath(l)}
          hrefLang={l}
          lang={l}
          aria-current={l === locale ? "true" : undefined}
          onClick={() => {
            document.cookie = `lang=${l}; path=/; max-age=31536000; samesite=lax`;
          }}
          className={cn("rounded-md px-2 py-1 transition-colors", l === locale ? "font-semibold text-foreground" : "text-muted-foreground hover:text-foreground")}
        >
          {localeNames[l]}
        </a>
      ))}
    </nav>
  );
}
