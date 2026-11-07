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
- Hold the right Option key, speak, release: the text is pasted into the app you are using. Speech recognition
  runs on your Mac (Whisper large-v3-turbo with voice-activity detection), built for Vietnamese mixed with English.
- AI cleanup of the text (fillers, punctuation, mis-heard terms, pronouns) with the service you choose: DeepSeek,
  Claude, OpenAI, Gemini, Kimi, OpenRouter, Ollama on your own machine, or any OpenAI-compatible address.
  An optional backup service takes over when the first one fails, and the notch tells you when it did.
- API keys are stored in the macOS Keychain, never on any server of ours. See PRIVACY.md.
- A personal dictionary, and corrections learned from how you use it.
- Casual (`tao/mày`) or neutral pronoun style per app, and per window title (for example Gmail).
- A menu-bar app with a pill that grows out of the notch, and a Settings window: Dictionary, Apps, AI and keys,
  Appearance, General.
- `whisper-server` is built into the app, and the two speech models (574 MB in total) download on first launch,
  resumable and checked against a fixed checksum. Nothing to install first.
- An app icon (a murmuration: a flock of small birds, one in clay) and an installer window that shows where to drag the
  app and what the first-launch "Open Anyway" row in System Settings looks like.
- The notch wave is a flock by default ("Bầy chim"): six small birds that sit flat when you are quiet and lift and open
  their wings, the brand's "v", as you speak; the newest is clay. The other wave styles are still in Settings.
- The mascot also speaks in empty, waiting and failed states (empty dictionary, scanning apps, engine stopped, a key test).
- A welcome window on first launch, with the mascot (a plump bird from the flock): what the app does, the three
  macOS permissions (each with its status and a button), the model download with its progress, and how to use it.
  It can be reopened from the menu ("Hướng dẫn ban đầu…").
- Optional pronunciation practice from the terminal (`murmr drill`, `murmr score`).

### Fixed
- A `whisper-server` could be left running (about 700 MB) after the app was closed abruptly. It now shuts down
  with the app, and a leftover is cleaned up on the next start.
- The app froze for several seconds on start while macOS checked a new build's access to the Keychain.
