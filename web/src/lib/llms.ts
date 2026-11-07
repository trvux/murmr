import { getDictionary } from "@/dictionaries";
import { localePath, type Locale } from "@/lib/i18n";
import { site } from "@/lib/site";

/** llms.txt: a short, link-rich summary for AI assistants, built from the same words as the site so they never disagree. */
export function llmsTxt(): string {
  const en = getDictionary("en");
  const link = (locale: Locale, label: string, note: string) => `- [${label}](${site.url}${localePath(locale)}): ${note}`;
  return [
    `# ${site.name}`,
    "",
    `> ${en.meta.description}`,
    "",
    "Murmr Stream is a free, open-source (MIT) dictation app for macOS with Apple Silicon. Speech recognition runs locally with Whisper; an optional AI step cleans up the text. It is built for Vietnamese mixed with English.",
    "",
    "## Pages",
    "",
    link("en", "Murmr Stream (English)", "what it is, how it works, features, privacy, download, FAQ"),
    link("vi", "Murmr Stream (Tiếng Việt)", "the same page in Vietnamese"),
    `- [Download](${site.url}/download): always the newest disk image`,
    "",
    "## Source and releases",
    "",
    `- [Source code and README](${site.repo}): MIT licence`,
    `- [Releases and changelog](${site.repo}/releases): every version, with notes and checksums`,
    `- [Privacy notes](${site.repo}/blob/main/PRIVACY.md): exactly what is and is not sent`,
    "",
    "## Full text",
    "",
    `- [llms-full.txt](${site.url}/llms-full.txt): the whole site as plain text`,
    "",
  ].join("\n");
}

/** llms-full.txt: the whole page as plain Markdown, in both languages. */
export function llmsFullTxt(): string {
  const parts: string[] = [`# ${site.name}`, ""];
  for (const locale of ["en", "vi"] as const) {
    const t = getDictionary(locale);
    parts.push(
      `## ${locale === "en" ? "English" : "Tiếng Việt"} (${site.url}${localePath(locale)})`,
      "",
      `**${t.hero.title}**`,
      "",
      t.hero.subtitle,
      "",
      `### ${t.how.title}`,
      ...t.how.steps.map((s, i) => `${i + 1}. **${s.title}**: ${s.text}`),
      "",
      `### ${t.features.title}`,
      ...t.features.items.map((f) => `- **${f.title}**: ${f.text}`),
      "",
      `### ${t.privacy.title}`,
      ...t.privacy.points.map((p) => `- **${p.title}**: ${p.text}`),
      "",
      `### ${t.faq.title}`,
      ...t.faq.items.flatMap((f) => [`**${f.q}**`, f.a, ""]),
    );
  }
  return parts.join("\n");
}
