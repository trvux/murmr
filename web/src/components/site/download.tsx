import Image from "next/image";
import { Download as DownloadIcon } from "lucide-react";
import { buttonVariants } from "@/components/ui/button";
import type { Dictionary } from "@/dictionaries";
import type { Locale } from "@/lib/i18n";
import { getLatestRelease } from "@/lib/release";
import { site } from "@/lib/site";
import { cn } from "@/lib/utils";
import { Reveal } from "./reveal";

export async function DownloadSection({ locale, t }: { locale: Locale; t: Dictionary["download"] }) {
  const release = await getLatestRelease();
  const date = release ? new Intl.DateTimeFormat(locale === "vi" ? "vi-VN" : "en-GB", { dateStyle: "long" }).format(new Date(release.publishedAt)) : null;
  const size = release?.dmgSize ? `${(release.dmgSize / 1_000_000).toFixed(1)} MB` : null;
  return (
    <div className="grid gap-10 lg:grid-cols-[0.9fr_1.1fr] lg:items-start">
      <Reveal>
        <div className="rounded-2xl border border-border bg-card p-7 md:p-9">
          <p className="text-muted-foreground">{t.text}</p>
          {/* a route handler that redirects to the file, not a page: a plain link is right */}
          {/* eslint-disable-next-line @next/next/no-html-link-for-pages */}
          <a href="/download" className={cn(buttonVariants({ size: "lg" }), "mt-7 h-12 w-full gap-2 text-base sm:w-auto sm:px-8")}>
            <DownloadIcon className="size-4" aria-hidden="true" />
            {t.button}
            {size ? <span className="font-normal opacity-70">· {size}</span> : null}
          </a>
          <p className="mt-3 text-sm text-muted-foreground">{t.requires}</p>
          {release ? (
            <dl className="mt-7 space-y-2.5 border-t border-border pt-6 text-sm">
              <div className="flex justify-between gap-4">
                <dt className="text-muted-foreground">{t.version}</dt>
                <dd className="font-mono">{release.version}</dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-muted-foreground">{t.released}</dt>
                <dd>{date}</dd>
              </div>
              {release.sha256 ? (
                <div className="gap-1">
                  <dt className="text-muted-foreground">{t.checksum}</dt>
                  <dd className="mt-1 break-all font-mono text-[11px] leading-relaxed text-muted-foreground">{release.sha256}</dd>
                </div>
              ) : null}
            </dl>
          ) : null}
          <div className="mt-6 flex flex-wrap gap-x-6 gap-y-2 text-sm">
            <a className="underline underline-offset-4 hover:text-signal" href={`${site.repo}/releases`} target="_blank" rel="noopener noreferrer">
              {t.github}
            </a>
            {release ? (
              <a className="underline underline-offset-4 hover:text-signal" href={release.notesUrl} target="_blank" rel="noopener noreferrer">
                {t.changelog}
              </a>
            ) : null}
          </div>
        </div>
      </Reveal>
      <Reveal delay={0.1}>
        <div>
          <h3 className="font-display text-2xl">{t.firstLaunchTitle}</h3>
          <p className="mt-3 max-w-xl text-muted-foreground">{t.firstLaunchText}</p>
          <Image src={`/images/first-launch-${locale}.png`} alt={t.firstLaunchAlt} width={1200} height={820} className="mt-6 w-full rounded-xl border border-border" />
        </div>
      </Reveal>
    </div>
  );
}
