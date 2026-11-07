# Changelog

All notable changes to Murmr Stream. The format follows [Keep a Changelog](https://keepachangelog.com), and the
version numbers follow [Semantic Versioning](https://semver.org): while the first number is 0, anything may still
change between releases.

The newest section below is what the GitHub release page shows for that version, so write it for the person
installing, not for the person reading the code. To publish a version, see "Releasing" in `CLAUDE.md`.

## [Unreleased]

## [0.1.0] - 2026-11-07

The first public build.

### Added
- Hold a key, speak, release: the text is pasted into the app you are using. The key is yours to choose (the right
  Option by default): another modifier on its own, a function key, or a combination, set in the welcome window or in
  Settings and changed at once. Speech recognition
  runs on your Mac (Whisper large-v3-turbo with voice-activity detection), built for Vietnamese mixed with English.
- AI cleanup of the text (fillers, punctuation, mis-heard terms, pronouns) with the service you choose: DeepSeek,
  Claude, OpenAI, Gemini, Kimi, OpenRouter, Ollama on your own machine, or any OpenAI-compatible address.
  An optional backup service takes over when the first one fails, and the notch tells you when it did.
- API keys are stored in the macOS Keychain, never on any server of ours. See PRIVACY.md.
- A personal dictionary, and corrections learned from how you use it.
- Your own way of addressing: the recognizer turns "tao" into "tôi" and "mày" into "bạn", so you define how you
  speak ("tao / mày / tụi tao", "tôi / bạn", "anh / em", anything) and where it applies: by default, per app, or per
  window title. Nothing is assumed out of the box: pronouns are left as recognised until you choose.
- A menu-bar app with a pill that grows out of the notch, and a Settings window: Dictionary, Apps, AI and keys,
  Appearance, General.
- `whisper-server` is built into the app, and the two speech models (574 MB in total) download on first launch,
  resumable and checked against a fixed checksum. Nothing to install first.
- An app icon (a murmuration: a flock of small birds, one in clay) and an installer window that shows where to drag the
  app and what the first-launch "Open Anyway" row in System Settings looks like.
- The notch wave is the brand's own drawn line by default ("Nét vẽ Murmr"): like the smooth-line style (five weaving lines,
  tapering at both ends, a swing that follows your voice) but made of the logo's wing-beat curves, and its colour follows
  your voice too: pale cream when you are quiet, rich clay when you speak up.
  The other wave styles are still in Settings.
- The mascot also speaks in empty, waiting and failed states (empty dictionary, scanning apps, engine stopped, a key test).
- A welcome window on first launch, with the mascot (a plump bird from the flock): what the app does, the three
  macOS permissions (each with its status and a button), the model download with its progress, and how to use it.
  It can be reopened from the menu ("Hướng dẫn ban đầu…").
- Optional pronunciation practice from the terminal (`murmr drill`, `murmr score`).

### Fixed
- Choosing the dictation key: a modifier pressed on its own (right Option, left Command, fn) was not noticed, so the
  box stayed on "Nhấn phím…". Modifiers are now read from the system, presses in the first moments are ignored, and
  "Đặt lại" is there while choosing too.
- A `whisper-server` could be left running (about 700 MB) after the app was closed abruptly. It now shuts down
  with the app, and a leftover is cleaned up on the next start.
- The app froze for several seconds on start while macOS checked a new build's access to the Keychain.
