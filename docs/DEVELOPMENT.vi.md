<p align="center"><a href="DEVELOPMENT.md">English</a> · <b>Tiếng Việt</b></p>

# Phát triển

Murmr Stream được build, cấu hình và chạy từ mã nguồn như thế nào. Muốn cài app để dùng, xem [README](../README.vi.md).

## Cấu trúc

Engine viết bằng Go nằm ở thư mục gốc của repo, còn vỏ app Swift nằm trong `app/`. Engine thu giọng nói, làm việc với
`whisper-server`, chạy bước AI dọn văn và dán kết quả. Vỏ app khởi động engine, hiển thị trạng thái của nó trên tai thỏ và
giữ cửa sổ Cài đặt.

## Build từ mã nguồn

Cần máy Mac chip Apple Silicon và Go 1.27 trở lên. Tuỳ chọn, cho công cụ luyện phát âm: `brew install uv espeak-ng ffmpeg`.

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

macOS sẽ hỏi quyền **Micro**, **Giám sát đầu vào** (để thấy phím nói của bạn) và **Trợ năng** (để dán chữ, và để một tổ
hợp phím không gõ ra chữ) cho terminal của bạn. Không có khoá dọn văn thì vẫn chạy, với chữ thô của Whisper.

## App macOS

`app/` là một app trên thanh menu (Swift, SwiftUI, không cần Xcode) chạy engine Go và vẽ trạng thái lên tai thỏ: một viên
thuốc đen mọc ra từ đó khi bạn giữ phím, hiện một đường sóng mảnh chạy theo giọng bạn, rồi "Đang chép lời" / "Đang dọn
văn", rồi đến chữ đã dán. Màn hình không có tai thỏ thì nó nổi dưới mép trên.

```sh
app/scripts/bundle.sh                 # build engine, whisper-server và "Murmr Stream.app" vào app/build/
open "app/build/Murmr Stream.app"
```

- **Người dùng không phải cài gì thêm.** App mang sẵn `whisper-server` của riêng nó: một file tự chứa, build từ whisper.cpp
  bằng `app/scripts/build-whisper.sh` (tĩnh, nhúng sẵn Metal, chạy trên macOS 14 trở lên; lần đầu `bundle.sh` tự chạy nó
  giúp bạn và cần `brew install cmake`). `whisper-cpp` của Homebrew chỉ cần để chạy từ terminal bằng `./run.sh`; nó liên kết
  thư viện bằng đường dẫn tuyệt đối và chỉ build cho macOS mới nhất, nên không thể bỏ vào app. Khi khởi động, engine cũng
  dừng một `whisper-server` mồ côi còn sót trên cổng của nó sau một lần chạy bị sập.
- **Cửa sổ chào.** Lần đầu mở (và từ menu) một hướng dẫn ngắn mời bạn chọn phím, đi qua ba quyền với trạng thái trực tiếp,
  rồi hiện tiến độ tải model. Nếu một bản cập nhật làm thiếu quyền, nó mở lại ở bước quyền, một lần cho mỗi bản build.
- **Quyền.** Với chữ ký ad-hoc, macOS quên chúng sau mỗi lần build lại; để giữ, hãy tạo một chứng chỉ ký mã tự cấp trong
  keychain và build bằng `MURMR_SIGN_ID="<tên của nó>" app/scripts/bundle.sh`.
- **Cài đặt** (biểu tượng trên thanh menu): trang từ điển (thuật ngữ, các cặp sửa cứng và các cặp học được từ lịch sử của
  bạn), trang xưng hô (các cách xưng hô của bạn, mặc định, và theo từng app hoặc tiêu đề cửa sổ; nó tự sửa `apps.txt` giúp
  bạn), trang AI (dịch vụ, khoá trong **Keychain của macOS**, thử khoá, các model khoá của bạn dùng được, và chính xác cái gì
  được gửi và không được gửi), trang giao diện (kiểu sóng và hình góc tai thỏ) và trang chung (trạng thái engine và phím nói).
- **Nhật ký** nằm ở `~/Library/Logs/Murmr Stream/engine.log`. Chữ bạn đọc chính tả không bao giờ được ghi vào đó.
- Mỗi lúc chỉ chạy được một engine (chúng dùng chung cổng 8178, micro và phím), nên hãy thoát `./run.sh` trước khi mở app.
- Phụ đề trực tiếp khi bạn đang nói có sẵn nhưng mặc định tắt (`MURMR_PREVIEW=on`): nó cần một Whisper server thứ hai nhanh
  hơn (thêm khoảng 600 MB RAM) và chỉ cập nhật khoảng mỗi 0,6 giây, vì Whisper mã hoá một cửa sổ cố định cho mỗi lần giải mã.

## Thiết kế

Diện mạo là một hệ thống có chủ ý, không phải mặc định: đọc [DESIGN.md](../DESIGN.md). Mọi giá trị hình ảnh nằm trong
`app/Sources/MurmrStream/Theme.swift`, `app/scripts/design-lint.sh` từ chối giá trị thô và các mẫu bị cấm, và
`MurmrStream --snapshot <dictionary|apps|ai|appearance|general|pills> out.png [dark]` vẽ giao diện ngoài màn hình để kiểm tra.

## Lệnh

| Lệnh | Việc nó làm |
|---|---|
| `./run.sh` | bắt đầu đọc chính tả (nạp `~/.config/murmr/env` trước) |
| `./murmr report` | các lỗi nghe sai lặp lại tìm thấy trong lịch sử của bạn |
| `./murmr forget "<chữ đã nghe>"` | thôi dùng một gợi ý đã học |
| `./murmr hints` | các cặp "nghe là => ý là" đã học dưới dạng JSON (cái cửa sổ Cài đặt hiển thị) |
| `./murmr fetch-models` | tải hai model giọng nói ngay bây giờ (app tự làm việc này ở lần mở đầu) |
| `./murmr providers` | các dịch vụ engine biết, dưới dạng JSON (cái trang AI vẽ ra) |
| `./murmr models <id>` | các model một dịch vụ cung cấp cho khoá của bạn, dưới dạng JSON (cái menu model hiển thị) |
| `./murmr holdkey-check <spec> [seconds]` | chạy bộ bắt phím thật và in `down` / `up` (ví dụ `combo:105:0` là F13, `mod:61` là ⌥ phải) |
| `./murmr pronouns` | các gợi ý khởi đầu cho một cách xưng hô, dưới dạng JSON (cái trang xưng hô đưa ra) |
| `./murmr clean [--as "tao / mày / tụi tao"] "<chữ>"` | chỉ chạy bước dọn văn, để thử đổi prompt hoặc một cách xưng hô |
| `./murmr drill` | đọc các câu luyện tập, nhận phản hồi đến từng âm vị và nghe lại bằng giọng của bạn |
| `./murmr progress` | độ chính xác theo tuần và nhóm âm nào khó nhất |
| `./murmr score <file.wav> "<chữ>"` | chấm điểm âm vị cho một bản ghi có sẵn |

## Dịch vụ AI và khoá API

Murmr Stream gọi một AI trên mạng cho **đúng một bước: dọn văn bản đã chép** (bỏ từ đệm, sửa dấu câu và từ nghe sai, xử lý
đại từ xưng hô). Nhận dạng giọng nói, VAD, chấm điểm âm vị và nghe lại bằng giọng của chính bạn đều chạy ngay trên máy và
không dùng API nào.

Các dịch vụ là những dòng trong một bảng duy nhất, `providers.go` (`./murmr providers` in nó ra, và cửa sổ Cài đặt vẽ từ
đó). Chỉ có hai giao thức: **tương thích OpenAI** (chat completions, phần lớn các dịch vụ) và **Anthropic Messages** (Claude).
Một dịch vụ gồm địa chỉ, tên biến khoá và model mặc định, cộng một đặc thù nhỏ tuỳ chọn (DeepSeek tắt chế độ suy nghĩ;
OpenAI không nhận `temperature`).

| Dịch vụ | Biến khoá | Địa chỉ | Đã thử với khoá thật |
|---|---|---|---|
| DeepSeek (mặc định khi có khoá của nó) | `DEEPSEEK_API_KEY` | `https://api.deepseek.com` | có (`deepseek-flash`) |
| Claude (Anthropic) | `ANTHROPIC_API_KEY` | `https://api.anthropic.com/v1` | có (`claude-haiku-4-5-20251001`) |
| OpenAI | `OPENAI_API_KEY` | `https://api.openai.com/v1` | **chưa** |
| Gemini (Google, lớp tương thích OpenAI) | `GEMINI_API_KEY` | `https://generativelanguage.googleapis.com/v1beta/openai` | **chưa** |
| Kimi (Moonshot) | `MOONSHOT_API_KEY` | `https://api.moonshot.ai/v1` | **chưa** |
| OpenRouter (nhiều hãng sau một khoá) | `OPENROUTER_API_KEY` | `https://openrouter.ai/api/v1` | **chưa** |
| Ollama (chạy ngay trên máy bạn, không cần khoá, chữ không rời máy) | không có | `http://localhost:11434/v1` (`OLLAMA_BASE_URL`) | **chưa** |
| Tự nhập (bất kỳ dịch vụ nào tương thích OpenAI, ví dụ LM Studio) | `CUSTOM_API_KEY` (tuỳ chọn) | `CUSTOM_BASE_URL` | **chưa** |

Các dịch vụ chưa thử thì không có model mặc định: bạn chọn một model trong danh sách do chính dịch vụ trả về (`./murmr
models <id>`). Địa chỉ phải là https, trừ máy này (`localhost`), để khoá không bao giờ bị gửi qua http thường tới một máy
khác. Bạn bị nhà cung cấp tính tiền theo từng yêu cầu; hãy xem bảng giá của họ. Chọn một dịch vụ bằng
`MURMR_CLEANUP=<id>`, hoặc `none` để không dùng API nào (khi đó bạn nhận chữ thô của Whisper). Để trống thì dịch vụ đầu tiên
trong bảng có khoá sẽ được dùng (dịch vụ không cần khoá không bao giờ được tự chọn).

**Đặt khoá ở đâu.** Trong app, dùng Cài đặt, trang AI: khoá đi vào Keychain của macOS (không đồng bộ qua iCloud) và app đưa
nó cho tiến trình engine của chính nó. Từ dòng lệnh, đặt nó trong `~/.config/murmr/env`, ngoài repo, với `chmod 600`;
`run.sh` nạp file đó, và app vẫn đọc nó như phương án dự phòng (trang này đề nghị chuyển khoá như vậy vào Keychain). Không
bao giờ đặt khoá trong cây mã nguồn hay trong một commit. Nếu một khoá bị lộ, hãy thu hồi nó ở nhà cung cấp ngay; xoá
commit là chưa đủ.

**Cái gì được gửi cùng mỗi lần đọc chính tả** (đây là danh sách đầy đủ):

- phần chữ đã chép (sau các sửa cứng `sai -> Đúng` trong từ điển của bạn);
- một system prompt gồm các quy tắc dọn văn, **các thuật ngữ trong từ điển cá nhân** (nên mọi tên riêng bạn thêm vào đó đều
  đến nhà cung cấp), **các gợi ý đã học** (các cặp "nghe là X, ý là Y" từ lịch sử của bạn) và một ghi chú ngắn về cách xưng hô.

**Cái gì không được gửi:** âm thanh, tên app đang dùng, tiêu đề cửa sổ, file lịch sử của bạn, hay khoá của bất kỳ nhà cung
cấp nào khác.

Nếu một yêu cầu thất bại hoặc quá 8 giây, chữ thô của Whisper được dán thay vào (hoặc, với `MURMR_FALLBACK=<id>`, dịch vụ
thứ hai đó được thử trước), nên đọc chính tả không bao giờ bị chặn bởi mạng. Nếu bạn trỏ một bản fork sang nhà cung cấp
khác, hãy đọc điều khoản lưu trữ dữ liệu của họ trước, vì chữ đọc chính tả có thể chứa những điều riêng tư.

## Cấu hình

Đặt trong `~/.config/murmr/env` (tất cả đều tuỳ chọn, trừ khoá dọn văn nếu bạn muốn dọn văn):

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `DEEPSEEK_API_KEY`, `ANTHROPIC_API_KEY` | không có | nhà cung cấp dọn văn (ưu tiên DeepSeek nếu có cả hai) |
| `<SERVICE>_MODEL` | tuỳ dịch vụ | tên model, ví dụ `DEEPSEEK_MODEL`, `ANTHROPIC_MODEL`, `OPENAI_MODEL` (lựa chọn trong Cài đặt thắng) |
| `MURMR_CLEANUP` | tự động | một id dịch vụ (`deepseek`, `claude`, `openai`...) hoặc `none` |
| `MURMR_FALLBACK` | tắt | một id dịch vụ: nếu dịch vụ đã chọn lỗi hoặc quá 6 giây, thử cái này (cần khoá riêng của nó; gửi chữ tới đó) |
| `MURMR_MODEL` | đã tải | đường dẫn model Whisper của riêng bạn; dùng nguyên trạng, không bao giờ tải |
| `MURMR_VAD` / `MURMR_VAD_MODEL` | bật / đã tải | `MURMR_VAD=off` tắt VAD; biến thứ hai là model VAD của riêng bạn |
| `MURMR_MODELS_DIR` | `~/Library/Application Support/Murmr Stream/models` | nơi lưu model đã tải (thư mục `./models/` trong thư mục làm việc được dùng trước, cho bản checkout mã nguồn) |
| `MURMR_HISTORY` | bật | `off` ngừng ghi `history.jsonl` |
| `MURMR_CONFIDENCE` | tắt | `on` thêm độ tin cậy từng từ, tốn khoảng 0,8 giây mỗi lần đọc |
| `MURMR_PREVIEW` / `MURMR_PREVIEW_PORT` | tắt / `8179` | `on` khởi động server thứ hai cho phụ đề trực tiếp (chỉ vỏ app) |
| `MURMR_SOUND_START/STOP/READY` | `Tink`/`Pop`/`Glass` | tên âm thanh hệ thống của macOS, hoặc `off` |
| `MURMR_KEY` | `mod:61` | phím nói: `mod:<mã phím>` cho một phím bổ trợ đứng một mình, `combo:<mã phím>:<cờ phím bổ trợ dạng hex>` nếu không (app tự ghi) |
| `MURMR_DICT`, `MURMR_PORT`, `MURMR_SAVE` | | đường dẫn từ điển, cổng whisper-server, thư mục lưu các đoạn ghi |

Quy tắc xưng hô nằm trong `~/.config/murmr/apps.txt`, mỗi dòng một quy tắc: `profile tao-may = tao / mày / tụi tao` định
nghĩa một cách xưng hô, `default tao-may` đặt mặc định, `<bundle id> tao-may` áp dụng cho một app, `title:<chữ> tao-may` cho
các cửa sổ có tiêu đề chứa chữ đó (`keep` để nguyên đại từ như nghe được). Trang xưng hô ghi file này giúp bạn.

## Công cụ luyện phát âm (tuỳ chọn)

`drill` và `score` dùng bộ nhận dạng âm vị chạy trên máy (wav2vec2 + espeak-ng IPA), được cài đặt trong
[`phoneme/`](../phoneme/README.md). Phần nghe lại "bằng giọng của chính bạn" là một thử nghiệm trong
[`voice/`](../voice/README.md): âm sắc của người học với cách phát âm chuẩn, để bạn nghe liền nhau lần thử của mình và bản
đúng.

## Phát hành

Xem mục "Releasing" trong [CLAUDE.md](../CLAUDE.md): phiên bản là file `VERSION`, ghi chú lấy từ
[CHANGELOG.md](../CHANGELOG.md), và đẩy một tag `v*` sẽ build file cài đặt trên GitHub rồi tạo một bản phát hành nháp.
