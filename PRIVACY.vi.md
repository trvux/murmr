<p align="center"><a href="PRIVACY.md">English</a> · <b>Tiếng Việt</b></p>

# Quyền riêng tư và điều khoản (bản nháp)

> **Tình trạng: bản nháp.** Phần quyền riêng tư bên dưới mô tả những gì mã nguồn làm hiện nay và đã được đối chiếu với nó.
> Phần điều khoản sử dụng chỉ là chỗ giữ chỗ để tác giả hoàn thiện. Đây không phải tư vấn pháp lý.

## Tóm tắt

- **Khoá API nằm trên máy bạn**, trong Keychain của macOS. Murmr Stream không có máy chủ, không có tài khoản, và không nhận
  khoá, giọng nói hay chữ nào của bạn.
- **Giọng nói của bạn không bao giờ rời máy.** Whisper chạy hoàn toàn trên máy Mac của bạn.
- Chỉ khi bạn **bật AI dọn văn**, phần **chữ đã chép** (cùng từ điển và gợi ý đã học của bạn) đi **thẳng từ máy bạn** tới
  dịch vụ bạn chọn (DeepSeek, Anthropic, OpenAI, Gemini, Kimi, OpenRouter hoặc một địa chỉ bạn tự nhập), kèm khoá của bạn.
  Dịch vụ đó có chính sách dữ liệu riêng.
- **Tắt AI thì không có gì rời máy.**
- Không có thu thập số liệu, phân tích hay báo cáo lỗi tự động.

## Murmr Stream là gì

Một app macOS (vỏ Swift) chạy một engine Go ngay trên máy bạn. Engine thu giọng nói khi bạn giữ phím, chép lời bằng
whisper.cpp chạy trên máy, có thể nhờ một dịch vụ AI trên mạng dọn lại chữ, và dán kết quả. Tác giả không vận hành máy chủ
nào, không có tài khoản, và không phải đăng nhập.

## Cái gì ở lại trên máy bạn

| Dữ liệu | Ở đâu | Ghi chú |
|---|---|---|
| Giọng nói của bạn | Chỉ trong bộ nhớ | Được chép lời trên máy. Không ghi ra đĩa trừ khi bạn đặt `MURMR_SAVE`. |
| Khoá API | Keychain đăng nhập của macOS. App không đánh dấu chúng là có thể đồng bộ, nên iCloud Keychain không chép chúng sang thiết bị khác (đã kiểm tra bằng một self-test). | Đặt trong Cài đặt, trang AI. Một khoá còn trong file `~/.config/murmr/env` cũ vẫn ở đó cho tới khi bạn chuyển hoặc xoá nó. |
| Các lần đọc chính tả (chữ thô và chữ cuối, id app) | `~/.config/murmr/history.jsonl` | Dùng để học những chỗ sửa lặp lại. Tắt bằng `MURMR_HISTORY=off`. Không có âm thanh. |
| Từ điển và quy tắc theo app | `~/.config/murmr/dictionary.txt`, `apps.txt` | Văn bản thường bạn sửa được. |
| Nhật ký engine | `~/Library/Logs/Murmr Stream/engine.log` | Thông báo khởi động và lỗi. Chữ bạn đọc không được ghi vào đó. |
| Tuỳ chọn | Cấu hình người dùng của macOS | Kiểu sóng, dịch vụ AI đã chọn và những thứ tương tự. |

## Cái gì rời khỏi máy bạn, và chỉ khi bạn bật AI dọn văn

Khi AI dọn văn bật, mỗi lần đọc chính tả gửi một yêu cầu **thẳng từ máy bạn** tới dịch vụ bạn chọn:

- **DeepSeek**: `https://api.deepseek.com/chat/completions`
- **Anthropic**: `https://api.anthropic.com/v1/messages`
- **OpenAI, Gemini, Kimi, OpenRouter**: địa chỉ `/chat/completions` của dịch vụ đó (xem [bảng dịch vụ](docs/DEVELOPMENT.vi.md#dịch-vụ-ai-và-khoá-api))
- **Tự nhập**: địa chỉ bạn gõ. Phải là https, trừ `localhost`.
- **Ollama** (hoặc bất kỳ máy chủ nào trên máy này): `http://localhost…`. Chữ ở lại trên máy bạn.

Yêu cầu chứa:

- phần chữ đã chép (sau các sửa cứng trong từ điển của bạn);
- các chỉ dẫn dọn văn, gồm **các thuật ngữ trong từ điển cá nhân** và **các gợi ý đã học** (các cặp "nghe là X, ý là Y" từ
  lịch sử của bạn), cộng một ghi chú ngắn về cách xưng hô;
- khoá API của bạn, dùng để xác thực với dịch vụ.

Nó **không** chứa âm thanh, tên app bạn đang đọc chính tả vào, tiêu đề cửa sổ, hay file lịch sử của bạn. Nếu một yêu cầu
thất bại hoặc quá 8 giây, chữ thô được dán thay vào. Nếu bạn bật "Tự chuyển sang … khi bị lỗi" trong Cài đặt (mặc định tắt,
và chỉ làm được khi có khoá cho cả hai dịch vụ), cũng phần chữ đó sẽ được gửi tới dịch vụ **còn lại** khi dịch vụ đã chọn
lỗi, và tai thỏ báo cho bạn biết khi điều đó xảy ra.

Riêng, khi bạn lưu một khoá hoặc mở Cài đặt, app hỏi cùng dịch vụ đó **danh sách model** của nó (ví dụ
`https://api.deepseek.com/models`, `https://api.anthropic.com/v1/models`). Yêu cầu này chỉ mang khoá của bạn, không có chữ
đã đọc.

Mỗi dịch vụ có điều khoản và chính sách dữ liệu riêng (một bên trung gian như OpenRouter thêm một bên nữa giữa bạn và
model). Hãy đọc chúng trước khi bật một dịch vụ, vì chữ đọc chính tả có thể chứa những điều riêng tư. Nếu bạn chọn "Không
dùng AI", không có chữ nào được gửi đi đâu cả.

## Bàn phím

Để biết lúc bạn giữ phím nói, engine đọc các sự kiện phím (Giám sát đầu vào) và chỉ so mã phím của chúng với phím bạn đã
chọn. Nó không đọc bạn gõ gì, và không có gì về các lần gõ phím được ghi ra đĩa, ghi nhật ký hay gửi đi đâu. Nếu bạn chọn
một tổ hợp phím, cùng bộ bắt phím đó giữ cho đúng tổ hợp ấy không đến được app đang ở phía trước khi bạn giữ nó (việc này
dùng quyền Trợ năng).

## Tác giả nhận được gì

Không gì cả. Mã nguồn không thực hiện cuộc gọi mạng nào khác: các địa chỉ duy nhất nó liên lạc là dịch vụ bạn chọn (và dịch
vụ dự phòng, nếu bạn bật), địa chỉ của dịch vụ tự nhập mà bạn gõ, và `127.0.0.1` (whisper server trên máy). Nó không có thu
thập số liệu, phân tích hay báo cáo sập. Các liên kết trong app (ví dụ "Lấy khoá") chỉ mở trong trình duyệt của bạn khi bạn
bấm vào.

## Xoá dữ liệu của bạn

Thoát app, rồi xoá:

- `~/.config/murmr/` (từ điển, quy tắc theo app, lịch sử, file env cũ)
- `~/Library/Logs/Murmr Stream/`
- `~/Library/Application Support/Murmr Stream/` (các model giọng nói đã tải)
- các mục Keychain dưới service `dev.trvux.murmr-stream` (Keychain Access, hoặc Cài đặt, trang AI, "Xoá khoá")
- tuỳ chọn của app (`defaults delete dev.trvux.murmr-stream`)

## Các lần tải về

Lần mở đầu tiên app tải hai model giọng nói, vì chúng quá lớn để mang sẵn trong app:

| File | Dung lượng | Từ đâu |
|---|---|---|
| `ggml-large-v3-turbo-q5_0.bin` (Whisper) | 574 MB | `huggingface.co/ggerganov/whisper.cpp` |
| `ggml-silero-v5.1.2.bin` (nhận diện giọng nói) | 0,9 MB | `huggingface.co/ggml-org/whisper-vad` |

Hugging Face chuyển hướng việc tải sang mạng phân phối nội dung của nó (`*.hf.co`). Yêu cầu là một HTTPS GET bình thường,
không mang khoá, tài khoản hay chữ đã đọc; máy chủ thấy được địa chỉ IP của bạn và tên app `Murmr-Stream`, như với mọi lần
tải khác. Mỗi file được kiểm tra với một SHA-256 và dung lượng cố định trước khi dùng, và một lần tải bị gián đoạn sẽ tiếp tục
từ chỗ dừng. Các file được đặt ở `~/Library/Application Support/Murmr Stream/models/` và bị xoá cùng thư mục đó. Đây là lần
duy nhất app tải thứ gì về; `./murmr fetch-models` làm việc tương tự từ terminal.

## Điều khoản sử dụng

*Do tác giả hoàn thiện.* Các chỗ giữ chỗ cần quyết định:

- Giấy phép: mã nguồn theo MIT (xem `LICENSE`). Các thành phần bên thứ ba giữ giấy phép riêng của chúng.
- Bảo hành và trách nhiệm: cung cấp "nguyên trạng" theo giấy phép MIT.
- Trách nhiệm về khoá API của chính bạn, chi phí do dịch vụ bạn chọn tính, và nội dung bạn đọc chính tả.
- Sử dụng được chấp nhận.
- Liên hệ cho câu hỏi và yêu cầu: *(thêm một địa chỉ)*.
