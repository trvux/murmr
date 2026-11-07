# murmr.phren.dev

The website for Murmr Stream: Next.js 16 (app router, Cache Components), bun, Tailwind v4, shadcn/ui and Motion. English and
Vietnamese, with SEO and GEO built in from the start.

```sh
bun install
bun run dev        # http://localhost:3000
bun run build && bun run start
bun run lint && bunx tsc --noEmit
```

## How it is organised

- `src/dictionaries/` holds every word on the site. `types.ts` is the shape; `en.ts` and `vi.ts` must both satisfy it, so the
  compiler fails when one language lacks what the other has. The examples on the page are real outputs of Murmr's own cleanup
  step, not hand-written ones.
- `src/proxy.ts` chooses the language. English is the canonical address (`/`), Vietnamese lives under `/vi`, and both are
  indexable with `hreflang`. A person is sent to `/vi` once, on a first visit, when their browser prefers Vietnamese (or, with
  no browser preference, when a `cf-ipcountry` / `x-country` header says VN); the choice is remembered in a cookie. Crawlers
  and link-preview bots are never redirected.
- `src/lib/seo.ts`, `src/app/robots.ts`, `src/app/sitemap.ts`, `src/app/llms.txt`, `src/app/llms-full.txt` and the JSON-LD in
  `src/app/[lang]/page.tsx` (Organization, WebSite, SoftwareApplication, FAQPage) are the search and AI-answer side.
- `src/lib/release.ts` reads the newest GitHub release (cached for an hour) for the version, date, size and checksum shown
  in the Download section; `/download` redirects to the newest disk image.
- Brand tokens (paper, ink, one clay accent, serif titles) are in `src/app/globals.css`, the same palette as the app
  (see `DESIGN.md` at the repo root).

Next 16 differs from older versions (for example `proxy.ts` replaces `middleware.ts`); `node_modules/next/dist/docs/` has the
guides that match the installed version.
