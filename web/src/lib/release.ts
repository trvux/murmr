import { cacheLife } from "next/cache";
import { site } from "@/lib/site";

export interface Release {
  version: string;
  publishedAt: string;
  notesUrl: string;
  dmgUrl: string;
  dmgSize: number | null;
  sha256: string | null;
}

/** The newest published release on GitHub. Cached for an hour; null when GitHub cannot be reached. */
export async function getLatestRelease(): Promise<Release | null> {
  "use cache";
  cacheLife("hours");
  try {
    const res = await fetch(`${site.repoApi}/releases/latest`, { headers: { Accept: "application/vnd.github+json" } });
    if (!res.ok) return null;
    const data = (await res.json()) as {
      tag_name: string;
      published_at: string;
      html_url: string;
      assets: { name: string; size: number; browser_download_url: string }[];
    };
    const dmg = data.assets.find((a) => a.name === "Murmr-Stream.dmg");
    const sum = data.assets.find((a) => a.name.endsWith(".dmg.sha256"));
    let sha256: string | null = null;
    if (sum) {
      const text = await (await fetch(sum.browser_download_url)).text();
      sha256 = text.trim().split(/\s+/)[0] ?? null;
    }
    return {
      version: data.tag_name.replace(/^v/, ""),
      publishedAt: data.published_at,
      notesUrl: data.html_url,
      dmgUrl: dmg?.browser_download_url ?? `${site.repo}/releases/latest/download/Murmr-Stream.dmg`,
      dmgSize: dmg?.size ?? null,
      sha256,
    };
  } catch {
    return null;
  }
}
