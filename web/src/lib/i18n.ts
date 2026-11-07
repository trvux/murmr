export const locales = ["en", "vi"] as const;
export type Locale = (typeof locales)[number];
export const defaultLocale: Locale = "en";

export const hasLocale = (value: string): value is Locale => (locales as readonly string[]).includes(value);

/** English is served without a prefix (the canonical address); Vietnamese lives under /vi. */
export function localePath(locale: Locale, path = "/"): string {
  const clean = path === "/" ? "" : path.replace(/\/$/, "");
  return locale === defaultLocale ? clean || "/" : `/${locale}${clean}`;
}

export const localeNames: Record<Locale, string> = { en: "English", vi: "Tiếng Việt" };
export const htmlLang: Record<Locale, string> = { en: "en", vi: "vi" };
export const ogLocale: Record<Locale, string> = { en: "en_US", vi: "vi_VN" };
