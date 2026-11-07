import type { Dictionary } from "@/dictionaries";
import type { Locale } from "@/lib/i18n";
import { localePath } from "@/lib/i18n";
import { site } from "@/lib/site";
import { Logo } from "./logo";

export function Footer({ locale, t }: { locale: Locale; t: Dictionary }) {
  const f = t.footer;
  return (
    <footer className="border-t border-border py-14">
      <div className="mx-auto grid max-w-6xl gap-10 px-5 md:grid-cols-[1.4fr_1fr_1fr_1fr] md:px-8">
        <div>
          <Logo locale={locale} label={t.nav.home} />
          <p className="mt-4 max-w-xs text-sm text-muted-foreground">{f.tagline}</p>
        </div>
        <FooterColumn title={f.product}>
          <a href={`${localePath(locale)}#features`}>{t.nav.features}</a>
          <a href={`${localePath(locale)}#use-cases`}>{t.nav.useCases}</a>
          <a href={`${localePath(locale)}#download`}>{t.nav.download}</a>
          <a href={`${localePath(locale)}#faq`}>{t.nav.faq}</a>
        </FooterColumn>
        <FooterColumn title={f.project}>
          <a href={site.repo} target="_blank" rel="noopener noreferrer">{f.source}</a>
          <a href={`${site.repo}/releases`} target="_blank" rel="noopener noreferrer">{t.download.changelog}</a>
          <a href={site.hub} rel="noopener">{f.hub}</a>
        </FooterColumn>
        <FooterColumn title={f.legal}>
          <a href={`${site.repo}/blob/main/${locale === "vi" ? "PRIVACY.vi.md" : "PRIVACY.md"}`} target="_blank" rel="noopener noreferrer">{f.privacy}</a>
          <a href={`${site.repo}/blob/main/LICENSE`} target="_blank" rel="noopener noreferrer">{f.license}</a>
        </FooterColumn>
      </div>
      <p className="mx-auto mt-12 max-w-6xl px-5 text-xs text-muted-foreground md:px-8">
        © 2026 Phren · {f.builtBy}
      </p>
    </footer>
  );
}

function FooterColumn({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="font-mono text-[11px] uppercase tracking-[0.18em] text-muted-foreground">{title}</p>
      <div className="mt-4 flex flex-col gap-2.5 text-sm [&_a]:text-foreground/80 [&_a:hover]:text-signal">{children}</div>
    </div>
  );
}
