import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

/**
 * Language choice, in one place.
 *
 * English is the canonical address ("/"); Vietnamese lives under "/vi". Both are real pages that search engines can index,
 * with hreflang between them. A person is sent to Vietnamese ONCE, on their first visit to an unprefixed address, when
 * their browser prefers Vietnamese (or, with no browser preference, when the country header says Vietnam); the choice is
 * then remembered in a cookie. Crawlers and link-preview bots are never redirected, so they always see the page they asked for.
 */

const BOTS =
  /bot|crawl|spider|slurp|facebookexternalhit|embedly|quora|whatsapp|telegram|preview|pinterest|linkedin|discord|slack|twitter|lighthouse|inspectiontool|gptbot|claude|perplexity|bytespider|amazonbot|applebot|ccbot|duckduckbot|yandex|baidu|petalbot/i;

function prefersVietnamese(request: NextRequest): boolean {
  const header = request.headers.get("accept-language");
  if (header) {
    const ranked = header
      .split(",")
      .map((part) => {
        const [tag, q] = part.trim().split(";q=");
        return { tag: tag.toLowerCase(), q: q ? Number(q) : 1 };
      })
      .filter((x) => x.tag && x.tag !== "*")
      .sort((a, b) => b.q - a.q);
    if (ranked[0]) return ranked[0].tag.startsWith("vi");
  }
  // No browser preference: the country, when something in front of us provides it (a CDN header or a GeoIP step).
  const country = request.headers.get("cf-ipcountry") ?? request.headers.get("x-country");
  return country?.toUpperCase() === "VN";
}

export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const first = pathname.split("/")[1];

  // "/en/..." is the same page as the unprefixed address: one canonical URL.
  if (first === "en") {
    const url = request.nextUrl.clone();
    url.pathname = pathname.replace(/^\/en/, "") || "/";
    return NextResponse.redirect(url, 308);
  }

  // Vietnamese is explicit in the URL: serve it, and remember that the person chose it.
  if (first === "vi") {
    const response = NextResponse.next();
    if (request.cookies.get("lang")?.value !== "vi") {
      response.cookies.set("lang", "vi", { path: "/", maxAge: 60 * 60 * 24 * 365, sameSite: "lax" });
    }
    return response;
  }

  // An unprefixed address: English, unless this is a person who has not chosen and prefers Vietnamese.
  const chosen = request.cookies.get("lang")?.value;
  const isBot = BOTS.test(request.headers.get("user-agent") ?? "");
  const wantsVietnamese = chosen ? chosen === "vi" : !isBot && prefersVietnamese(request);
  if (wantsVietnamese && !isBot) {
    const url = request.nextUrl.clone();
    url.pathname = `/vi${pathname === "/" ? "" : pathname}`;
    const response = NextResponse.redirect(url, 302);
    response.cookies.set("lang", "vi", { path: "/", maxAge: 60 * 60 * 24 * 365, sameSite: "lax" });
    response.headers.set("Cache-Control", "private, no-store");
    response.headers.set("Vary", "Accept-Language, Cookie");
    return response;
  }

  const url = request.nextUrl.clone();
  url.pathname = `/en${pathname === "/" ? "" : pathname}`;
  const response = NextResponse.rewrite(url);
  response.headers.set("Vary", "Accept-Language, Cookie");
  return response;
}

export const config = {
  // Pages only: not files, the API, framework internals or the download redirect.
  matcher: ["/((?!_next|api|download|robots.txt|sitemap.xml|llms.txt|llms-full.txt|favicon.ico|icon|apple-icon|images|.*\\..*).*)"],
};
