import { Code2, KeyRound, Lock, ShieldCheck } from "lucide-react";
import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { buttonVariants } from "@/components/ui/button";
import { CleanupDemo } from "@/components/site/cleanup-demo";
import { DownloadSection } from "@/components/site/download";
import { Faq } from "@/components/site/faq";
import { Footer } from "@/components/site/footer";
import { Header } from "@/components/site/header";
import { JsonLd } from "@/components/site/json-ld";
import { PillDemo } from "@/components/site/pill-demo";
import { Reveal } from "@/components/site/reveal";
import { Section } from "@/components/site/section";
import { WpmTest } from "@/components/site/wpm-test";
import { getDictionary } from "@/dictionaries";
import { hasLocale, htmlLang, localePath } from "@/lib/i18n";
import { pageMetadata } from "@/lib/seo";
import { site } from "@/lib/site";
import { cn } from "@/lib/utils";

export async function generateMetadata({ params }: PageProps<"/[lang]">): Promise<Metadata> {
  const { lang } = await params;
  if (!hasLocale(lang)) return {};
  return pageMetadata(lang, getDictionary(lang));
}

const privacyIcons = [ShieldCheck, Lock, KeyRound, Code2];

export default async function Home({ params }: PageProps<"/[lang]">) {
  const { lang } = await params;
  if (!hasLocale(lang)) notFound();
  const t = getDictionary(lang);
  const url = `${site.url}${localePath(lang)}`;

  const graph = {
    "@context": "https://schema.org",
    "@graph": [
      { "@type": "Organization", "@id": `${site.hub}/#org`, name: "Phren", url: site.hub, logo: `${site.url}/icon.png`, sameAs: [site.repo] },
      { "@type": "WebSite", "@id": `${site.url}/#website`, url: site.url, name: site.name, inLanguage: htmlLang[lang], publisher: { "@id": `${site.hub}/#org` } },
      {
        "@type": "SoftwareApplication",
        "@id": `${site.url}/#app`,
        name: site.name,
        url,
        description: t.meta.description,
        applicationCategory: "ProductivityApplication",
        operatingSystem: "macOS 14 or later (Apple Silicon)",
        inLanguage: ["en", "vi"],
        license: "https://opensource.org/license/mit",
        isAccessibleForFree: true,
        offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
        downloadUrl: `${site.url}/download`,
        codeRepository: site.repo,
        image: `${site.url}/images/og-${lang}.png`,
        author: { "@type": "Person", name: site.author },
        publisher: { "@id": `${site.hub}/#org` },
      },
      {
        "@type": "FAQPage",
        mainEntity: t.faq.items.map((item) => ({ "@type": "Question", name: item.q, acceptedAnswer: { "@type": "Answer", text: item.a } })),
      },
    ],
  };

  return (
    <>
      <JsonLd data={graph} />
      <Header locale={lang} t={t} />
      <main>
        {/* hero */}
        <section className="relative overflow-hidden">
          <div className="mx-auto grid max-w-6xl gap-14 px-5 pb-20 pt-14 md:px-8 md:pb-28 md:pt-20 lg:grid-cols-[1.05fr_0.95fr] lg:items-center">
            <div>
              <p className="font-mono text-xs uppercase tracking-[0.18em] text-signal">{t.hero.eyebrow}</p>
              <h1 className="mt-4 font-display text-[2.9rem] leading-[1.02] tracking-tight sm:text-6xl lg:text-[4.4rem]">{t.hero.title}</h1>
              <p className="mt-6 max-w-xl text-lg leading-relaxed text-muted-foreground md:text-xl">{t.hero.subtitle}</p>
              <div className="mt-9 flex flex-wrap items-center gap-4">
                <a href="#download" className={cn(buttonVariants({ size: "lg" }), "h-12 px-7 text-base")}>
                  {t.hero.cta}
                </a>
                <a href="#how" className="text-base text-foreground underline decoration-border underline-offset-8 transition-colors hover:text-signal hover:decoration-signal">
                  {t.hero.secondary}
                </a>
              </div>
              <p className="mt-4 text-sm text-muted-foreground">{t.hero.ctaNote}</p>
            </div>
            <PillDemo labels={t.hero.demo} />
          </div>
          <div className="border-y border-border bg-secondary/50">
            <dl className="mx-auto grid max-w-6xl grid-cols-2 gap-x-6 gap-y-8 px-5 py-9 md:grid-cols-4 md:px-8">
              {t.proof.map((p) => (
                <div key={p.label}>
                  <dt className="font-display text-3xl md:text-4xl">{p.value}</dt>
                  <dd className="mt-1.5 text-sm leading-snug text-muted-foreground">{p.label}</dd>
                </div>
              ))}
            </dl>
          </div>
        </section>

        <Section id="speed" eyebrow={t.wpm.eyebrow} title={t.wpm.title} intro={t.wpm.intro}>
          <WpmTest t={t.wpm} />
        </Section>

        <Section id="how" eyebrow={t.how.eyebrow} title={t.how.title} className="bg-secondary/40">
          <ol className="grid gap-6 md:grid-cols-3">
            {t.how.steps.map((step, i) => (
              <Reveal key={step.title} delay={i * 0.08}>
                <li className="h-full rounded-2xl border border-border bg-card p-7">
                  <span className="font-display text-5xl text-signal/80">{i + 1}</span>
                  <h3 className="mt-5 font-display text-2xl">{step.title}</h3>
                  <p className="mt-3 leading-relaxed text-muted-foreground">{step.text}</p>
                </li>
              </Reveal>
            ))}
          </ol>
        </Section>

        <Section id="cleanup" eyebrow={t.cleanup.eyebrow} title={t.cleanup.title} intro={t.cleanup.intro}>
          <CleanupDemo t={t.cleanup} />
        </Section>

        <Section id="features" eyebrow={t.features.eyebrow} title={t.features.title} className="bg-secondary/40">
          <div className="grid gap-5 md:grid-cols-2 lg:grid-cols-3">
            {t.features.items.map((f, i) => (
              <Reveal key={f.title} delay={(i % 3) * 0.07}>
                <article className="h-full rounded-2xl border border-border bg-card p-6 transition-colors hover:border-foreground/25">
                  <h3 className="font-display text-xl">{f.title}</h3>
                  <p className="mt-2.5 leading-relaxed text-muted-foreground">{f.text}</p>
                </article>
              </Reveal>
            ))}
          </div>
        </Section>

        <Section id="use-cases" eyebrow={t.useCases.eyebrow} title={t.useCases.title} intro={t.useCases.intro}>
          <div className="grid gap-5 md:grid-cols-2 lg:grid-cols-3">
            {t.useCases.items.map((u, i) => (
              <Reveal key={u.who} delay={(i % 3) * 0.07}>
                <article className="flex h-full flex-col rounded-2xl border border-border bg-card p-6">
                  <h3 className="font-mono text-xs uppercase tracking-[0.16em] text-signal">{u.who}</h3>
                  <p className="mt-4 text-xs uppercase tracking-wider text-muted-foreground">{t.useCases.sayLabel}</p>
                  <p className="mt-1.5 font-mono text-[13px] leading-relaxed text-muted-foreground">{u.say}</p>
                  <p className="mt-5 text-xs uppercase tracking-wider text-muted-foreground">{t.useCases.getLabel}</p>
                  <p className="mt-1.5 font-display text-lg leading-snug">{u.get}</p>
                </article>
              </Reveal>
            ))}
          </div>
        </Section>

        <Section id="privacy" eyebrow={t.privacy.eyebrow} title={t.privacy.title} intro={t.privacy.intro} className="bg-secondary/40">
          <div className="grid gap-5 md:grid-cols-2">
            {t.privacy.points.map((p, i) => {
              const Icon = privacyIcons[i % privacyIcons.length];
              return (
                <Reveal key={p.title} delay={(i % 2) * 0.08}>
                  <div className="flex h-full gap-4 rounded-2xl border border-border bg-card p-6">
                    <Icon className="mt-1 size-5 shrink-0 text-signal" aria-hidden="true" />
                    <div>
                      <h3 className="font-display text-xl">{p.title}</h3>
                      <p className="mt-2 leading-relaxed text-muted-foreground">{p.text}</p>
                    </div>
                  </div>
                </Reveal>
              );
            })}
          </div>
          <div className="mt-8 flex flex-wrap gap-x-8 gap-y-2 text-sm">
            <a className="underline underline-offset-4 hover:text-signal" href={`${site.repo}/blob/main/${lang === "vi" ? "PRIVACY.vi.md" : "PRIVACY.md"}`} target="_blank" rel="noopener noreferrer">
              {t.privacy.link}
            </a>
            <a className="underline underline-offset-4 hover:text-signal" href={site.repo} target="_blank" rel="noopener noreferrer">
              {t.privacy.openSource}
            </a>
          </div>
        </Section>

        <Section id="download" eyebrow={t.download.eyebrow} title={t.download.title}>
          <DownloadSection locale={lang} t={t.download} />
        </Section>

        <Section id="faq" eyebrow={t.faq.eyebrow} title={t.faq.title} className="bg-secondary/40">
          <Faq t={t.faq} />
        </Section>
      </main>
      <Footer locale={lang} t={t} />
    </>
  );
}
