import { buttonVariants } from "@/components/ui/button";
import type { Dictionary } from "@/dictionaries";
import type { Locale } from "@/lib/i18n";
import { cn } from "@/lib/utils";
import { LanguageSwitch } from "./language-switch";
import { Logo } from "./logo";

export function Header({ locale, t }: { locale: Locale; t: Dictionary }) {
  const links = [
    ["#features", t.nav.features],
    ["#use-cases", t.nav.useCases],
    ["#privacy", t.nav.privacy],
    ["#faq", t.nav.faq],
  ] as const;
  return (
    <header className="sticky top-0 z-40 border-b border-border/70 bg-background/85 backdrop-blur-md">
      <div className="mx-auto flex h-16 max-w-6xl items-center justify-between gap-4 px-5 md:px-8">
        <Logo locale={locale} label={t.nav.home} />
        <nav aria-label="Primary" className="hidden items-center gap-7 text-sm text-muted-foreground md:flex">
          {links.map(([href, label]) => (
            <a key={href} href={href} className="transition-colors hover:text-foreground">
              {label}
            </a>
          ))}
        </nav>
        <div className="flex items-center gap-3">
          <LanguageSwitch locale={locale} label={t.nav.language} />
          <a href="#download" className={cn(buttonVariants({ size: "sm" }), "hidden sm:inline-flex")}>
            {t.nav.download}
          </a>
        </div>
      </div>
    </header>
  );
}
