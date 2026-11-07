# Murmr Stream: notes for Claude

Go engine at the repo root, Swift/SwiftUI app shell in `app/`.

## Build and test

- Engine: `go vet ./... && go test ./... && go build -o murmr .`
- App: `cd app && swift build -c release`
- Bundle the `.app`: `app/scripts/bundle.sh`. Set `MURMR_SIGN_ID="Murmr Stream Dev"` so macOS keeps the
  granted permissions (Microphone, Input Monitoring, Accessibility) across rebuilds; ad-hoc signing
  resets them every time.
- `bundle.sh` needs `app/vendor/whisper-server`; if missing it runs `app/scripts/build-whisper.sh` (needs cmake).
  Never copy Homebrew's whisper-server into the app: dynamic libraries and macOS-27-only.
- GitHub's runner has an older Swift compiler than a developer Mac. Long mixed CGFloat/Double expressions that build
  locally fail there with "unable to type-check this expression in reasonable time", so write drawing maths as short typed
  steps (`let x: CGFloat = ...`). CI is where this shows up; a green local build does not prove it.
- Quit the running app before opening a new build (`open` on a running app only focuses the old one).

## Documents come in two languages

`README`, `PRIVACY` and `docs/DEVELOPMENT` each exist as `X.md` (English) and `X.vi.md` (Vietnamese), with a language link
in the first line. Change both in the same commit and run `scripts/check-docs.sh` (CI runs it): it fails when one side
gains a section, table row, code block, image or link the other lacks. `CHANGELOG.md` stays English (the release notes
come from it); the release page footer (`.github/release-footer.md`) carries both languages.

## The website (`web/`)

murmr.phren.dev: Next.js 16 + bun + shadcn/ui + Motion, English and Vietnamese. Read `web/README.md` first, and the guides in
`web/node_modules/next/dist/docs/` (this Next differs from older ones). Every word is in `web/src/dictionaries` (one type, two
languages); examples shown as "real outputs" must come from running `murmr clean`, never hand-written. Check with
`cd web && bunx tsc --noEmit && bun run lint && bun run build`; CI runs the same (`.github/workflows/web.yml`). Do not name
other products on the site. Changes to the VPS, DNS or the Caddyfile there need the user's explicit yes.

## Interface languages

The app speaks English and Vietnamese (`L10n.swift`). Words in the code are Vietnamese and are the keys; English lives in
`app/Resources/en.lproj/Localizable.strings`. When you add or change interface text: write it in Vietnamese, add the English
entry, put plain-`String` text through `tr("...")`, and pass values as `tr("... %@", value)` (never `\(value)` inside the
literal). `scripts/check-strings.sh` (CI) enforces it; look at the result with `--snapshot <page> out.png lang=en`. The engine's
own notices use `ui(vi, en)` in `uitext.go`. Pictures for the README are drawn by `app/scripts/docs-images.sh`.

## UI work: brand first, code second

Read `DESIGN.md` before changing anything visual. The product has one deliberate look (quiet
editorial: paper, ink, one clay accent, serif titles, hairlines, a single black pill).

1. Every colour, font, radius, space and animation comes from `app/Sources/MurmrStream/Theme.swift`.
   Do not write raw values in views. Need something new? Add a token to Theme with a role name.
2. Run `app/scripts/design-lint.sh`; it must pass.
3. Look at the result: `MurmrStream --snapshot appearance|general|pills out.png [dark]` renders offscreen
   (no screen-recording permission needed). Check light and dark. Read the PNG and critique it against
   the checklist at the end of `DESIGN.md`.
4. Reject the AI defaults listed in `DESIGN.md` (purple gradients, glass, card soup, gradient icon tiles,
   bounce, shadows on content).

## Releasing

Versions are `VERSION` (one line, `0.1.0`). `bundle.sh` writes it into the app and the engine; the tag, the .dmg name and
the release page all follow it. The workflow also uploads the same .dmg as `Murmr-Stream.dmg` (fixed name) for the README's
direct link. Only versions with a dash (`1.0.0-beta`) are marked pre-release, because `/releases/latest` skips those.

1. Move the entries under `## [Unreleased]` in `CHANGELOG.md` into a new `## [x.y.z] - YYYY-MM-DD` section, written for
   the person installing. The release workflow takes that section as the release notes and fails if it is missing.
2. Put `x.y.z` in `VERSION`. Commit ("Release x.y.z").
3. The user pushes: `git push origin main` then `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. GitHub Actions (`.github/workflows/release.yml`) builds on a macos-15 runner (macos-14 runners were retired 2026-11-02), makes the .dmg and its checksum, and creates a
   **draft** release. Check it on the Releases page, download the .dmg in a browser (this adds the quarantine flag, the
   same as for a stranger), drag it to Applications and open it, then press **Publish release**.
5. A wrong release: delete the draft and the tag (`git push origin :vX.Y.Z`), fix, tag again.

`app/scripts/make-dmg.sh` makes the same .dmg locally (after `bundle.sh`). Never commit the .dmg or `app/vendor/`.
