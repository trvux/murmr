
---

## Cài đặt / Install

1. Tải file `.dmg` ở mục **Assets** bên dưới, mở nó, kéo **Murmr Stream** vào **Applications**.
2. Lần đầu mở, macOS sẽ báo không xác minh được nhà phát triển (app chưa được Apple công chứng).
   Cách mở: vào **System Settings → Privacy & Security**, kéo xuống, bấm **Open Anyway** cho Murmr Stream.
   (Trên macOS 14 cũng có thể bấm chuột phải vào app, chọn **Open**.)
3. Cấp các quyền khi macOS hỏi: Microphone, Input Monitoring, Accessibility.
4. Lần mở đầu app tải hai model giọng nói (574 MB), cần mạng một lần.

Open the `.dmg` below, drag **Murmr Stream** into **Applications**. The first launch is blocked by Gatekeeper because
the app is not notarized: open **System Settings → Privacy & Security** and click **Open Anyway**.
Needs a Mac with Apple Silicon and macOS 14 or later.

Checksum: `shasum -a 256 -c Murmr-Stream-<version>.dmg.sha256` (file in Assets). Privacy: [PRIVACY.md](https://github.com/trvux/murmr/blob/main/PRIVACY.md).
