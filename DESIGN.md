# Murmr Stream: design brief

Read this before touching any UI. Every visual value lives in `app/Sources/MurmrStream/Theme.swift`;
views never invent their own. `app/scripts/design-lint.sh` enforces that.

## The big idea: speak softly, be heard ("nói khẽ, nghe rõ")

Murmr is a quiet tool. You murmur, it hears everything, and the words appear where you were
already looking. The interface should feel like a well-set page, not a dashboard: calm, warm,
unhurried, exact. The only dark, loud object in the whole product is the black pill on the notch;
everything else stays on paper.

Personality: **calm, warm, precise**. Not: playful, techy, glossy, urgent.

## What we are not (anti-references)

These are the defaults AI-built UI falls into. Reject them on sight.

- Purple/indigo/blue gradients, anywhere (logo, buttons, selection, backgrounds).
- Frosted-glass panels as the default surface.
- Every section in the same bordered, shadowed card ("card soup"); cards inside cards.
- Gradient app-icon tiles holding SF Symbols (the System Settings clone).
- Rounded display fonts, neon glows, bouncy or elastic motion, emoji as decoration.
- Dense dashboard layouts and "three feature cards in a row".

## Palette (paper and ink, one accent)

Colours are named by role and are dynamic (light and dark). No raw `Color(red:)` outside Theme.

| Token | Light | Dark | Used for |
|---|---|---|---|
| `paper` | `#F6F2E9` | `#161412` | page background |
| `paperRaised` | `#FBF9F4` | `#1E1B18` | inputs, mock windows |
| `paperSunken` | `#EEE9DD` | `#121110` | sidebar |
| `ink` | `#1D1A15` | `#EFE9DC` | primary text, primary button |
| `inkMuted` | `#6E675B` | `#A59E90` | secondary text |
| `inkFaint` | `#A39C8E` | `#6B655A` | tertiary text |
| `rule` | ink at 12% | ink at 14% | hairlines and borders |
| `signal` | `#B5532F` (clay) | `#E0825C` | the single accent: selection, recording |
| `sage` | `#4F7A5E` | `#7FB08D` | success only |
| `pillBody` | `#000000` | `#000000` | the notch pill (must match the hardware notch) |
| `pillInk` | `#F6F2E9` | `#F6F2E9` | everything drawn on the pill |

One accent only. `signal` replaces the usual "recording red" so the product has a single warm voice.

## Type (system fonts only: New York, SF Pro, SF Mono)

Five sizes. Nothing else.

| Token | Spec | Used for |
|---|---|---|
| `display` | 30 serif regular | page titles |
| `title` | 17 serif semibold | wordmark, section titles |
| `body` / `bodyStrong` | 13 SF Pro | text, row titles |
| `caption` | 12 SF Pro | descriptions, status |
| `label` | 11 SF Pro semibold, uppercase, tracked | eyebrows, small badges |
| `mono` | 12 SF Mono | paths, key names |

The serif carries the editorial voice; SF Pro carries the product; mono marks anything that is
literally a key, a path or a command.

## Shape, space, elevation

- Radii: `sm` 6 (chips, nav items), `md` 10 (tiles, buttons, inputs), `lg` 18 (the pill).
- Spacing is a 4pt scale: `xs 4`, `s 8`, `m 12`, `l 16`, `xl 24`, `xxl 32`, `huge 48`.
- Structure comes from whitespace and hairline rules, not boxes. Boxes are for things you choose
  between (the wave tiles) and for the preview.
- No drop shadows on content. No glow. The pill is the only thing allowed to feel heavy.
- Reading measure: page content is at most 680pt wide.

## Motion

Calm and short. Ease-out about 0.28 s, or a well-damped spring (no overshoot). Motion explains
state (the pill widening, the wave moving), never decorates.

## Icons

SF Symbols, one weight, monochrome, `inkMuted` (or `ink` when selected). No coloured tiles.
The mark is typographic: "Murmr" in the serif with a small tracked "STREAM" beneath.

## Voice and copy

Plain Vietnamese, sentence case, no exclamation marks, no jargon where a plain word exists.
Short sentences. Say what happens ("Giữ để nói, thả ra để dán"), not how clever it is.
The UI never uses "tao/mày"; that is for the user's own dictation, not for the app's voice.

## Checklist before calling a UI done

1. `app/scripts/design-lint.sh` passes (no literals outside Theme).
2. Render with `MurmrStream --snapshot <page> out.png` in light and `dark`, and look at it.
3. None of the anti-references above appear.
4. At most five type sizes and three radii are on screen; spacing sits on the 4pt scale.
5. Text contrast is at least 4.5:1 (secondary text included).
6. Exactly one accent colour is visible.
