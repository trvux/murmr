# Murmr Stream

Hold a key, speak, release: your words appear in whatever app has focus. A free, local-first
dictation tool for macOS, built for **Vietnamese mixed with English**, written in Go.
(The repo and the command are both called `murmr`.)

Inspired by [Wispr Flow](https://wisprflow.ai). Not affiliated with it.

```
hold RIGHT Option -> microphone (16 kHz)
   -> whisper-server (local, model stays loaded, Metal)  -> raw text
   -> DeepSeek / Claude cleanup (fillers, punctuation, mis-heard terms, pronouns)
   -> clipboard + Cmd+V into the focused app
```

## What it does

- **Hold-to-talk** on the right Option key (a listen-only `CGEventTap`; the key still works normally).
- **Local speech-to-text**: whisper.cpp `large-v3-turbo` (q5_0) behind `whisper-server`, with Silero VAD so
  silence and noise are ignored instead of turned into invented text.
- **LLM cleanup** with DeepSeek (default) or Claude Haiku: removes fillers, fixes punctuation and
  mis-heard English tech terms, keeps mixed Vietnamese/English as spoken. If the API fails or times out,
  the raw transcript is pasted.
- **Personal dictionary** (`~/.config/murmr/dictionary.txt`): terms and `wrong -> Right` fixes, fed to
  both Whisper's prompt and the LLM.
- **Learns from use**: recurring "heard X, meant Y" corrections found in your history become soft
  hints for the LLM.
- **Per-app pronoun style**: casual (`tao/mày`) in terminals and AI apps, neutral elsewhere, with
  window-title rules (e.g. a browser tab ending in "- Gmail" is neutral).
- **Pronunciation practice** (`drill`): phoneme-level feedback, optionally replayed in your own voice.

## Status

Built and tested on one machine (MacBook Pro M2 Pro, macOS) and mostly with one speaker.
Measured there: about 1.8 s to transcribe a 20 s clip, and roughly 2-3 s from releasing the key to the
text being pasted. Whisper still mishears English tech terms spoken with a Vietnamese accent
(for example `crash` as `cache`); the cleanup step fixes many of these from context but not all.
The phoneme scorer was only validated on synthetic voices and one real speaker, so treat its numbers
as relative, not absolute.

## Requirements

macOS on Apple Silicon, Go 1.27+, and:

```sh
brew install whisper-cpp
```

Optional, for the pronunciation tools: `brew install uv espeak-ng ffmpeg`.

## Install

```sh
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

macOS will ask for **Microphone**, **Input Monitoring** (the Option key) and **Accessibility** (pasting)
for your terminal. Without a cleanup key it still works, with raw Whisper output.

## Commands

| Command | What it does |
|---|---|
| `./run.sh` | start dictating (loads `~/.config/murmr/env` first) |
| `./murmr report` | recurring mishearings found in your history |
| `./murmr forget "<heard text>"` | stop using a learned hint |
| `./murmr clean [--casual] "<text>"` | run only the cleanup step, to try prompt changes |
| `./murmr drill` | read practice sentences, get phoneme-level feedback and a replay in your voice |
| `./murmr progress` | weekly accuracy and which sound classes are hardest |
| `./murmr score <file.wav> "<text>"` | phoneme-score an existing recording |

## Configuration

Set in `~/.config/murmr/env` (all optional except a cleanup key if you want cleanup):

| Variable | Default | Meaning |
|---|---|---|
| `DEEPSEEK_API_KEY`, `ANTHROPIC_API_KEY` | none | cleanup provider (DeepSeek preferred if both are set) |
| `DEEPSEEK_MODEL` | `deepseek-flash` | DeepSeek model name |
| `MURMR_CLEANUP` | auto | `deepseek`, `claude` or `none` |
| `MURMR_MODEL` | `models/ggml-large-v3-turbo-q5_0.bin` | Whisper model path |
| `MURMR_VAD` / `MURMR_VAD_MODEL` | on / `models/ggml-silero-v5.1.2.bin` | `MURMR_VAD=off` disables VAD |
| `MURMR_HISTORY` | on | `off` stops writing `history.jsonl` |
| `MURMR_CONFIDENCE` | off | `on` adds per-word confidence, costs about 0.8 s per dictation |
| `MURMR_SOUND_START/STOP/READY` | `Tink`/`Pop`/`Glass` | macOS system sound names, or `off` |
| `MURMR_DICT`, `MURMR_PORT`, `MURMR_SAVE` | | dictionary path, whisper-server port, directory to save clips |

App rules live in `~/.config/murmr/apps.txt` (`<bundle id> casual|neutral` or `title:<text> casual|neutral`).

## Pronunciation tools (optional)

`drill` and `score` use a local phoneme recognizer (wav2vec2 + espeak-ng IPA), set up in
[`phoneme/`](phoneme/README.md). The replay "in your own voice" is an experiment in
[`voice/`](voice/README.md): the learner's timbre with native pronunciation, so you can hear your
attempt and the correct version back to back.

## Privacy

- Audio is processed locally and is not stored unless you set `MURMR_SAVE`.
- **The transcript text of each dictation is sent to the cleanup provider** (DeepSeek or Anthropic)
  unless you set `MURMR_CLEANUP=none`.
- `~/.config/murmr/history.jsonl` stores raw and final text locally (no audio), mode `0600`.
- Drill and voice features use your own recordings, kept on your machine. API keys are read from the
  environment and are never part of this repository.

## License

No license has been chosen yet, so all rights are reserved for now.
