# Murmr Stream: notes for Claude

Go engine at the repo root, Swift/SwiftUI app shell in `app/`.

## Build and test

- Engine: `go vet ./... && go test ./... && go build -o murmr .`
- App: `cd app && swift build -c release`
- Bundle the `.app`: `app/scripts/bundle.sh`. Set `MURMR_SIGN_ID="Murmr Stream Dev"` so macOS keeps the
  granted permissions (Microphone, Input Monitoring, Accessibility) across rebuilds; ad-hoc signing
  resets them every time.
- Quit the running app before opening a new build (`open` on a running app only focuses the old one).

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
