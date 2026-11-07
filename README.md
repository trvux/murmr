<p align="center"><b>English</b> · <a href="README.vi.md">Tiếng Việt</a></p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/banner-dark.png">
    <img src="docs/banner-light.png" alt="Murmr Stream" width="820">
  </picture>
</p>

# Murmr Stream

**Hold a key, speak, release. Your words appear in whatever app has focus.**

A free, local-first dictation app for macOS, built for **Vietnamese mixed with English**. Speech recognition runs on
your Mac. An optional AI step cleans up the text.

[![Download](https://img.shields.io/badge/Download-for%20Mac-1c1a16?style=flat-square)](https://github.com/trvux/murmr/releases/latest/download/Murmr-Stream.dmg)
[![Release](https://img.shields.io/github/v/release/trvux/murmr?style=flat-square&color=b5532f)](https://github.com/trvux/murmr/releases/latest)
[![Platform](https://img.shields.io/badge/macOS-14%2B%20·%20Apple%20Silicon-blue?style=flat-square)](#install)
[![License](https://img.shields.io/github/license/trvux/murmr?style=flat-square)](LICENSE)

<p align="center">
  <img src="docs/screenshots/notch.png" alt="The pill that grows out of the notch: listening, transcribing, done, and an error" width="560">
</p>

## How it works

```
hold your key -> microphone (16 kHz)
   -> whisper-server (on your Mac, the model stays loaded, Metal)   -> raw text
   -> AI cleanup (optional: fillers, punctuation, mis-heard terms)  -> clean text
   -> pasted into the app in front (Cmd+V)
```

You choose the key. It can be a modifier on its own (the right Option by default), a function key, or a combination.

## Features

| | |
|---|---|
| **Hold to talk** | Any key or combination you pick, changed at once with no restart. Nothing you type is recorded. |
| **Local speech to text** | whisper.cpp `large-v3-turbo` with voice-activity detection, so silence and noise are ignored instead of turned into invented words. |
| **AI cleanup** | Removes fillers, fixes punctuation and mis-heard English tech terms, keeps Vietnamese and English as you spoke them. Works with DeepSeek, Claude, OpenAI, Gemini, Kimi, OpenRouter, Ollama on your own machine, or any OpenAI-compatible address. Without a key you still get the raw text. |
| **Your own way of addressing** | Say it the way you speak: "tao / mày", "tôi / bạn", "mình / cậu", "anh / em". Set a default, or one per app or per window title. Nothing is assumed for you. |
| **Personal dictionary** | Names, terms and `wrong -> Right` fixes, fed to both Whisper and the AI. It also learns recurring corrections from how you use it. |
| **Private by design** | No account, no server of ours, no telemetry. Keys live in the macOS Keychain. See [PRIVACY.md](PRIVACY.md). |

<p align="center">
  <img src="docs/screenshots/pronouns.png" alt="The addressing page of the Settings window" width="720">
</p>

> The app's own interface is in Vietnamese for now.

## Install

1. [Download **Murmr-Stream.dmg**](https://github.com/trvux/murmr/releases/latest/download/Murmr-Stream.dmg), open it and drag **Murmr Stream** into **Applications**.
2. Eject the disk image, then open the app **from Applications** (not from inside the disk image: macOS would run a
   temporary copy and forget the permissions you give it).
3. **The first time, macOS blocks it**, because the app is not notarized by Apple (that costs a yearly fee this free
   project does not pay yet). It is a one-time step: dismiss the warning ("Done"), open **System Settings → Privacy &
   Security**, scroll to **Security** and click **Open Anyway**, then confirm with your password or Touch ID.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/first-launch-dark.png">
  <img src="docs/first-launch.png" alt="The three steps for the first launch: dismiss the warning, open Privacy &amp; Security, click Open Anyway" width="820">
</picture>

Then a short welcome window asks you to choose your dictation key, allow the three permissions macOS asks for, and
downloads the speech models (574 MB, once). Needs a Mac with Apple Silicon and macOS 14 or later (built for 14, tested on
macOS 15 and later).

<p align="center">
  <img src="docs/screenshots/welcome.png" alt="The welcome window: choose the key you hold to talk" width="360">
</p>

## Use it

1. Click into any text field.
2. Hold your key and speak.
3. Release. The text is pasted a moment later (about 2 to 3 seconds for a short sentence on an M2 Pro).

Settings live in the menu bar icon: dictionary, addressing, AI service and key, appearance, and the dictation key.

## Questions

**macOS says the app cannot be opened.** That is the first-launch step above: **System Settings → Privacy & Security → Open Anyway**.

**A permission shows "not granted" although its switch is on.** macOS ties a permission to one build of one app, in one
place. Make sure you opened the app from Applications, then in the System Settings list click **−** to remove Murmr
Stream and **+** to add it again.

**I pressed the key and nothing happened.** All three permissions (Microphone, Input Monitoring, Accessibility) must be
granted, and the models must have finished downloading. The welcome window shows both; reopen it from the menu bar icon.

**Does it work without an AI key?** Yes. You get the raw transcript, which is already usable.

**What leaves my Mac?** Audio never does. With AI cleanup on, the transcript text goes straight from your Mac to the
service you chose. Turn the AI off and nothing leaves. The full list is in [PRIVACY.md](PRIVACY.md).

## Status

Built and tested on one machine (MacBook Pro M2 Pro) and mostly with one speaker. Whisper still mishears English tech
terms spoken with a Vietnamese accent (for example `crash` as `cache`); the cleanup step fixes many of these from
context, not all.

## For developers

Building from source, the engine commands, every setting, the AI service table and the design rules are in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). Changes per version are in [CHANGELOG.md](CHANGELOG.md).

## License

MIT, see [LICENSE](LICENSE). Pieces you download separately (whisper.cpp and its models, the Silero VAD model, OpenVoice,
the wav2vec2 phoneme model, espeak-ng) have their own licenses; check them before redistributing anything that includes them.
