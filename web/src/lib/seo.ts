import type { Metadata } from "next";
import { htmlLang, localePath, locales, ogLocale, type Locale } from "@/lib/i18n";
import { site } from "@/lib/site";
import type { Dictionary } from "@/dictionaries/types";

/** hreflang links for one page: every language, plus x-default pointing at English. */
export function alternates(locale: Locale, path = "/") {
  const languages: Record<string, string> = {};
  for (const l of locales) languages[htmlLang[l]] = `${site.url}${localePath(l, path)}`;
  languages["x-default"] = `${site.url}${localePath("en", path)}`;
  return { canonical: `${site.url}${localePath(locale, path)}`, languages };
}

export function pageMetadata(locale: Locale, t: Dictionary, path = "/"): Metadata {
  const url = `${site.url}${localePath(locale, path)}`;
  const image = `${site.url}/images/og-${locale}.png`;
  return {
    metadataBase: new URL(site.url),
    title: t.meta.title,
    description: t.meta.description,
    keywords: t.meta.keywords,
    authors: [{ name: site.author }],
    alternates: alternates(locale, path),
    openGraph: {
      type: "website",
      url,
      siteName: site.name,
      title: t.meta.title,
      description: t.meta.description,
      locale: ogLocale[locale],
      alternateLocale: locales.filter((l) => l !== locale).map((l) => ogLocale[l]),
      images: [{ url: image, alt: t.meta.ogAlt }],
    },
    twitter: { card: "summary_large_image", title: t.meta.title, description: t.meta.description, images: [image] },
    robots: { index: true, follow: true, googleBot: { index: true, follow: true, "max-image-preview": "large", "max-snippet": -1 } },
  };
}
