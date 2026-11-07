<p align="center"><b>English</b> · <a href="DEVELOPMENT.vi.md">Tiếng Việt</a></p>

# Development

How Murmr Stream is built, configured and run from source. For installing the app, see the [README](../README.md).

## Layout

The Go engine is at the repository root and the Swift app shell is in `app/`. The engine records the voice, talks to
`whisper-server`, runs the AI cleanup and pastes the result. The app shell starts the engine, shows its state on the notch
and holds the Settings window.

## Build from source

Needs macOS on Apple Silicon and Go 1.27 or later. Optional, for the pronunciation tools: `brew install uv espeak-ng ffmpeg`.

```sh
brew install whisper-cpp
git clone https://github.com/trvux/murmr && cd murmr
go build -o murmr .

mkdir -p models
curl -L -o models/ggml-large-v3-turbo-q5_0.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
curl -L -o models/ggml-silero-v5.1.2.bin \
  https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin

mkdir -p ~/.config/murmr && chmod 700 ~/.config/murmr
echo 'export DEEPSEEK_API_KEY=...' > ~/.config/murmr/env && chmod 600 ~/.config/murmr/env
./run.sh
```

macOS asks for **Microphone**, **Input Monitoring** (to see your dictation key) and **Accessibility** (pasting, and keeping
a key combination from typing) for your terminal. Without a cleanup key it still works, with raw Whisper output.

## The macOS app

`app/` is a menu-bar app (Swift, SwiftUI, no Xcode needed) that runs the Go engine and draws the state on the notch: a
black pill grows out of it while you hold the key, shows a slim wave that follows your voice, then "Transcribing" /
"Cleaning up" ("Đang chép lời" / "Đang dọn văn" in Vietnamese), then the pasted text. On a screen without a notch it floats under the top edge.

```sh
app/scripts/bundle.sh                 # builds the engine, whisper-server and "Murmr Stream.app" into app/build/
open "app/build/Murmr Stream.app"
```

- **Nothing to install for users.** The app carries its own `whisper-server`: one self-contained file built from
  whisper.cpp by `app/scripts/build-whisper.sh` (static, Metal embedded, runs on macOS 14 or later; the first
  `bundle.sh` runs it for you and needs `brew install cmake`). Homebrew's `whisper-cpp` is only needed to run from a
  terminal with `./run.sh`; it links libraries by absolute path and is built for the newest macOS only, so it cannot be
  copied into an app. On start the engine also stops an orphaned `whisper-server` left on its port by a crashed run.
- **Welcome window.** On first launch (and from the menu) a short guide has you choose your key (and, in its corner, the language), walks through the three
  permissions with live status, then shows the model download. If an update leaves a permission missing, it opens again at
  the permissions step, once per build.
- **Permissions.** With ad-hoc signing macOS forgets them on every rebuild; to keep them, create a self-signed
  code-signing certificate in your keychain and build with `MURMR_SIGN_ID="<its name>" app/scripts/bundle.sh`.
- **Settings** (menu bar icon): a dictionary page (terms, hard fixes and the pairs learned from your history), an
  addressing page (your ways of addressing, the default, and per app or per window title; it edits `apps.txt` for you), an
  AI page (service, key in the **macOS Keychain**, a key test, the models your key can use, and exactly what is and is not
  sent), an appearance page (wave style and notch corner shape) and a general page (engine status and the dictation key).
- **Logs** go to `~/Library/Logs/Murmr Stream/engine.log`. The dictated text is never written there.
- Only one engine can run at a time (they share port 8178, the microphone and the key), so quit `./run.sh` before opening the app.
- Live captions while you speak exist but are off by default (`MURMR_PREVIEW=on`): they need a second, faster Whisper
  server (about 600 MB more RAM) and only update about every 0.6 s, because Whisper encodes a fixed window per decode.

## Languages of the interface

The app speaks English and Vietnamese. The setting is **Automatic** (Vietnamese when the Mac's first language is Vietnamese,
English otherwise), or a fixed choice, kept in the `uiLanguage` preference and changed live from Settings, General.

- The words in the code are Vietnamese and are the keys. English is `app/Resources/en.lproj/Localizable.strings`; Vietnamese
  needs no file. Literal text in a SwiftUI `Text("...")` is looked up by SwiftUI, and words that reach the screen as plain
  strings go through `tr("...")` (see `L10n.swift`). A value goes in with `tr("... %@", value)`, never inside the literal.
- The Go engine words a few notices itself (an error, "the backup answered"). The app sets its language with `MURMR_LANG` at
  start and a `lang vi|en` line on stdin (`uitext.go`). The AI service descriptions in `providers.go` have English entries in
  the same strings file.
- `scripts/check-strings.sh` (run in CI) fails when a Vietnamese word that reaches the screen has no English entry, is written
  where nothing translates it, or has a value mixed into the literal. The self-test checks the language logic.
- `app/scripts/docs-images.sh` draws the banner, first-launch guide and screenshots in both languages into `docs/en/` and
  `docs/vi/`, with sample data instead of yours. The disk image's background cannot switch language, so it says both.

To add a language: copy `en.lproj` to `<code>.lproj`, translate the values, add the code to `UILanguage` and to
`CFBundleLocalizations` in `Info.plist`, and have the engine word its notices in it.

## Design

The look is a deliberate system, not defaults: read [DESIGN.md](../DESIGN.md). All visual values live in
`app/Sources/MurmrStream/Theme.swift`, `app/scripts/design-lint.sh` rejects raw values and banned patterns, and
`MurmrStream --snapshot <dictionary|apps|ai|appearance|general|pills> out.png [dark] [lang=en|vi]` renders the UI offscreen to check it.

## Commands

| Command | What it does |
|---|---|
| `./run.sh` | start dictating (loads `~/.config/murmr/env` first) |
| `./murmr report` | recurring mishearings found in your history |
| `./murmr forget "<heard text>"` | stop using a learned hint |
| `./murmr hints` | the learned "heard => meant" pairs as JSON (what the Settings window shows) |
| `./murmr fetch-models` | download the two speech models now (the app does it on first launch) |
| `./murmr providers` | the services the engine knows, as JSON (what the AI page draws) |
| `./murmr models <id>` | the models a service offers for your key, as JSON (what the model menu shows) |
| `./murmr holdkey-check <spec> [seconds]` | run the real key tap and print `down` / `up` (e.g. `combo:105:0` is F13, `mod:61` the right Option) |
| `./murmr pronouns` | the starting points for a way of addressing, as JSON (what the addressing page offers) |
| `./murmr clean [--as "tao / mày / tụi tao"] "<text>"` | run only the cleanup step, to try prompt changes or a way of addressing |
| `./murmr drill` | read practice sentences, get phoneme-level feedback and a replay in your voice |
| `./murmr progress` | weekly accuracy and which sound classes are hardest |
| `./murmr score <file.wav> "<text>"` | phoneme-score an existing recording |

## AI services and API keys

Murmr Stream calls a hosted AI for **one step only: cleaning up the transcript** (removing fillers, fixing punctuation and
mis-heard terms, handling pronouns). Speech recognition, VAD, phoneme scoring and the own-voice replay all run locally and
use no API.

Services are rows in one table, `providers.go` (`./murmr providers` prints it, and the Settings window draws from it). There
are only two wire protocols: **OpenAI-compatible** chat completions (most services) and **Anthropic Messages** (Claude). A
service is its address, key variable and default model, plus an optional small quirk (DeepSeek turns thinking off; OpenAI
gets no `temperature`).

| Service | Key variable | Address | Checked with a real key |
|---|---|---|---|
| DeepSeek (default when its key is set) | `DEEPSEEK_API_KEY` | `https://api.deepseek.com` | yes (`deepseek-flash`) |
| Claude (Anthropic) | `ANTHROPIC_API_KEY` | `https://api.anthropic.com/v1` | yes (`claude-haiku-4-5-20251001`) |
| OpenAI | `OPENAI_API_KEY` | `https://api.openai.com/v1` | **no** |
| Gemini (Google, OpenAI-compatible layer) | `GEMINI_API_KEY` | `https://generativelanguage.googleapis.com/v1beta/openai` | **no** |
| Kimi (Moonshot) | `MOONSHOT_API_KEY` | `https://api.moonshot.ai/v1` | **no** |
| OpenRouter (many labs behind one key) | `OPENROUTER_API_KEY` | `https://openrouter.ai/api/v1` | **no** |
| Ollama (runs on your machine, no key, text never leaves it) | none | `http://localhost:11434/v1` (`OLLAMA_BASE_URL`) | **no** |
| Custom (any OpenAI-compatible service, e.g. LM Studio) | `CUSTOM_API_KEY` (optional) | `CUSTOM_BASE_URL` | **no** |

Services not yet checked have no default model: you pick one from the list the service itself returns (`./murmr models <id>`).
An address must be https, except for this machine (`localhost`), so a key is never sent over plain http to another host. You
are billed by the provider per request; check their pricing. Pick one with `MURMR_CLEANUP=<id>`, or `none` to use no API at
all (you then get raw Whisper output). Left unset, the first service in the table that has a key is used (services that need
no key are never picked automatically).

**Where to put keys.** In the app, use Settings, the AI page: the key goes to the macOS Keychain (not synced to iCloud) and
the app hands it to its own engine process. From the command line, put it in `~/.config/murmr/env`, outside the repository,
with `chmod 600`; `run.sh` loads that file, and the app still reads it as a fallback (the page offers to move such a key into
the Keychain). Never put a key in the source tree or in a commit. If one leaks, revoke it at the provider right away;
deleting the commit is not enough.

**What is sent with every dictation** (this is the full list):

- the transcript text (after your `wrong -> Right` dictionary fixes);
- a system prompt made of the cleanup rules, the **terms from your personal dictionary** (so any names you add there go to
  the provider), the **learned hints** (pairs of "heard X, meant Y" from your history) and a short pronoun-style note.

**What is not sent:** audio, the focused app's name, window titles, your history file, or any other provider's key.

If a request fails or takes longer than 8 seconds, the raw Whisper text is pasted instead (or, with `MURMR_FALLBACK=<id>`, that
second service is tried first), so dictation never blocks on the network. If you point a fork at another provider, read that
provider's data-retention terms first, because dictation text can contain private things.

## Configuration

Set in `~/.config/murmr/env` (all optional except a cleanup key if you want cleanup):

| Variable | Default | Meaning |
|---|---|---|
| `DEEPSEEK_API_KEY`, `ANTHROPIC_API_KEY` | none | cleanup provider (DeepSeek preferred if both are set) |
| `<SERVICE>_MODEL` | per service | model name, e.g. `DEEPSEEK_MODEL`, `ANTHROPIC_MODEL`, `OPENAI_MODEL` (the Settings choice wins) |
| `MURMR_CLEANUP` | auto | a service id (`deepseek`, `claude`, `openai`...) or `none` |
| `MURMR_FALLBACK` | off | a service id: if the chosen service fails or takes over 6 s, try this one (needs its own key; sends the text there) |
| `MURMR_MODEL` | downloaded | path of your own Whisper model; used as is, never downloaded |
| `MURMR_VAD` / `MURMR_VAD_MODEL` | on / downloaded | `MURMR_VAD=off` disables VAD; the second is your own VAD model |
| `MURMR_MODELS_DIR` | `~/Library/Application Support/Murmr Stream/models` | where downloaded models go (a `./models/` folder in the working directory is used first, for source checkouts) |
| `MURMR_HISTORY` | on | `off` stops writing `history.jsonl` |
| `MURMR_CONFIDENCE` | off | `on` adds per-word confidence, costs about 0.8 s per dictation |
| `MURMR_PREVIEW` / `MURMR_PREVIEW_PORT` | off / `8179` | `on` starts the second server for live captions (app shell only) |
| `MURMR_SOUND_START/STOP/READY` | `Tink`/`Pop`/`Glass` | macOS system sound names, or `off` |
| `MURMR_KEY` | `mod:61` | the dictation key: `mod:<key code>` for a modifier alone, `combo:<key code>:<modifier flags in hex>` otherwise (the app writes it) |
| `MURMR_DICT`, `MURMR_PORT`, `MURMR_SAVE` | | dictionary path, whisper-server port, directory to save clips |

Pronoun rules live in `~/.config/murmr/apps.txt`, one per line: `profile tao-may = tao / mày / tụi tao` defines a way of
addressing, `default tao-may` sets the default, `<bundle id> tao-may` applies to one app, `title:<text> tao-may` to window
titles containing that text (`keep` leaves pronouns as recognised). The addressing page writes this for you.

## Pronunciation tools (optional)

`drill` and `score` use a local phoneme recognizer (wav2vec2 + espeak-ng IPA), set up in [`phoneme/`](../phoneme/README.md).
The replay "in your own voice" is an experiment in [`voice/`](../voice/README.md): the learner's timbre with native
pronunciation, so you can hear your attempt and the correct version back to back.

## Releasing

See "Releasing" in [CLAUDE.md](../CLAUDE.md): the version is the `VERSION` file, the notes come from
[CHANGELOG.md](../CHANGELOG.md), and pushing a `v*` tag builds the disk image on GitHub and creates a draft release.
