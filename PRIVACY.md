# Privacy and terms (draft)

> **Status: draft.** The privacy section below describes what the code does today and was checked against
> it. The terms of use are a placeholder to be completed by the author. This is not legal advice.

## Tóm tắt (Vietnamese summary)

- **Khoá API nằm trên máy bạn**, trong Keychain của macOS. Murmr Stream không có máy chủ, không tạo tài khoản,
  không nhận khoá, giọng nói hay chữ của bạn.
- **Giọng nói không rời máy.** Whisper chạy hoàn toàn trên máy bạn.
- Chỉ khi bạn **bật AI dọn văn**, phần **chữ đã chép** (cùng từ điển và gợi ý đã học) được gửi **thẳng từ máy bạn**
  tới dịch vụ bạn chọn (DeepSeek hoặc Anthropic), kèm khoá của bạn. Dịch vụ đó có chính sách dữ liệu riêng.
- **Tắt AI thì không có gì rời máy.**
- Không có telemetry, analytics hay báo cáo lỗi tự động.

## What Murmr Stream is

A macOS app (a Swift shell) that runs a Go engine on your computer. The engine records your voice while you
hold a key, transcribes it with whisper.cpp running locally, optionally has a hosted AI service clean up the
text, and pastes the result. There is no server operated by the author, no account, and no sign-in.

## What stays on your computer

| Data | Where | Notes |
|---|---|---|
| Your voice | Memory only | Transcribed locally. Not written to disk unless you set `MURMR_SAVE`. |
| API keys | Your macOS login Keychain. The app does not mark them as synchronizable, so iCloud Keychain does not copy them to other devices (checked with a self-test). | Set in Settings, "AI và khoá API". A key left in the older `~/.config/murmr/env` file stays there until you move or delete it. |
| Dictations (raw and final text, app id) | `~/.config/murmr/history.jsonl` | Used to learn recurring corrections. Turn off with `MURMR_HISTORY=off`. No audio. |
| Dictionary and app rules | `~/.config/murmr/dictionary.txt`, `apps.txt` | Plain text you can edit. |
| Engine log | `~/Library/Logs/Murmr Stream/engine.log` | Startup and error messages. The dictated text is not written to it. |
| Preferences | macOS user defaults | Wave style, chosen AI service, and similar. |

## What leaves your computer, and only if you enable AI cleanup

When AI cleanup is on, each dictation sends one request **directly from your computer** to the service you chose:

- **DeepSeek**: `https://api.deepseek.com/chat/completions`
- **Anthropic**: `https://api.anthropic.com/v1/messages`

The request contains:

- the transcript text (after your "sửa cứng" dictionary fixes);
- the cleanup instructions, which include the **terms from your personal dictionary** and the **learned
  hints** (pairs of "heard X, meant Y" from your history), plus a short pronoun-style note;
- your API key, as the service's authentication.

It does **not** contain audio, the name of the app you are dictating into, window titles, or your history file.
If a request fails or takes longer than 8 seconds, the raw transcript is pasted instead.
If you turn on "Tự chuyển sang … khi bị lỗi" in Settings (off by default, and only possible with a key for both
services), the same text is then sent to the **other** service when the chosen one fails, and the notch tells you
when that happened.

Separately, when you save a key or open Settings, the app asks the same service for its **list of models**
(`https://api.deepseek.com/models`, `https://api.anthropic.com/v1/models`). That request carries only your key,
no dictated text.

DeepSeek and Anthropic have their own terms and data policies. Read them before enabling a service, because
dictated text can contain private things. If you choose "Không dùng AI", no text is sent anywhere.

## What the author receives

Nothing. The code makes no other network calls: the only addresses it contacts are the two services above (when
you enable them) and `127.0.0.1` (the local whisper server). It has no telemetry, analytics or crash reporting.
Links in the app (for example "Lấy khoá") open in your browser only when you click them.

## Removing your data

Quit the app, then delete:

- `~/.config/murmr/` (dictionary, app rules, history, old env file)
- `~/Library/Logs/Murmr Stream/`
- the Keychain items under the service `dev.trvux.murmr-stream` (Keychain Access, or Settings, "AI và khoá API",
  "Xoá khoá")
- the app's preferences (`defaults delete dev.trvux.murmr-stream`)

## Downloads

*To be completed when first-run model download is added:* the Whisper model and the voice-activity model are
fetched from Hugging Face on first launch.

## Terms of use

*To be completed by the author.* Placeholders to decide:

- Licence: the source code is MIT (see `LICENSE`). Third-party components keep their own licences.
- Warranty and liability: provided "as is" under the MIT licence.
- Responsibility for your own API keys, costs billed by the service you choose, and the content you dictate.
- Acceptable use.
- Contact for questions and requests: *(add an address)*.
