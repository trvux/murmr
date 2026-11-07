import type { MetadataRoute } from "next";
import { alternates } from "@/lib/seo";
import { localePath, locales } from "@/lib/i18n";
import { site } from "@/lib/site";

const pages = ["/"];

export default function sitemap(): MetadataRoute.Sitemap {
  const lastModified = new Date();
  return pages.flatMap((path) =>
    locales.map((locale) => ({
      url: `${site.url}${localePath(locale, path)}`,
      lastModified,
      changeFrequency: "weekly" as const,
      priority: path === "/" ? 1 : 0.7,
      alternates: { languages: alternates(locale, path).languages },
    })),
  );
}
