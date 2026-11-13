# SCOAI Voice (bản OpenAI)

**Phiên dịch cuộc họp trực tiếp trên điện thoại Android: Việt · Trung · Anh, theo mọi chiều.**
Mỗi câu hiện hai dòng: lời gốc và bản dịch. Bạn có thể phát biểu lại bằng tiếng của đối phương. Họp xong có tóm tắt, hỏi đáp và biên bản để gửi Zalo.

> *English summary: a live meeting interpreter for Android (Vietnamese, Chinese, English). Bilingual captions per sentence, a "speak back" button that voices your reply in the other side's language through the loudspeaker, quick questions during the meeting, sentence explanations, photo-to-glossary context, summaries, Q&A and shareable minutes. All AI runs through the OpenAI API (`gpt-realtime-translate`, `gpt-transcribe`, `gpt-6-luna`, `gpt-6.1-terra`).*

Giao diện theo SCOAI Voice (bản dịch offline). Khác ở chỗ bản này giao mọi việc AI cho OpenAI API, máy không chạy model nào. Mã gói Android là `com.scoai.voice.openai`, khác bản offline (`com.scoai.voice`), nên cài được cả hai trên một máy.

## Mục lục

- [Bài toán](#bài-toán)
- [Tính năng](#tính-năng)
- [Cài đặt nhanh](#cài-đặt-nhanh)
- [Cách dùng](#cách-dùng)
- [Chế độ thử (không cần khoá)](#chế-độ-thử-không-cần-khoá)
- [Model OpenAI và chi phí](#model-openai-và-chi-phí)
- [Khoá API và quyền riêng tư](#khoá-api-và-quyền-riêng-tư)
- [Build từ mã nguồn](#build-từ-mã-nguồn)
- [Kiến trúc](#kiến-trúc)
- [Kiểm thử](#kiểm-thử)
- [Giới hạn và việc chưa làm](#giới-hạn-và-việc-chưa-làm)

## Bài toán

Người Việt họp, đàm phán hay làm việc với đối tác nói tiếng Trung hoặc tiếng Anh thường gặp ba việc:
- Không theo kịp cuộc nói chuyện.
- Không đáp lại được ngay bằng tiếng của đối phương.
- Sau buổi họp không có biên bản rõ ràng: đã chốt gì, ai làm việc gì.

Thuê phiên dịch thì tốn kém và không phải lúc nào cũng có. Gõ từng câu vào app dịch thì quá chậm cho một cuộc họp thật.

SCOAI Voice giải quyết cả ba bằng AI:
- dịch trực tiếp từng câu;
- phát biểu lại bằng giọng nói tiếng của đối phương;
- tự tóm tắt và trả lời câu hỏi về nội dung cuộc họp.

## Tính năng

### Cuộc họp trực tiếp
- **Phụ đề song ngữ:** mỗi câu có nhãn ngôn ngữ (Việt / Trung / Anh), dòng gốc nhỏ màu xám, và bản dịch chữ lớn kèm vạch màu bên trái. Câu đã đúng ngôn ngữ đích chỉ hiện một dòng.
- **Cả hai | Gốc | Dịch:** chọn xem cả hai dòng, chỉ lời gốc, hoặc chỉ bản dịch. Phễu lọc chỉ hiện các câu nói bằng một ngôn ngữ.
- **Tự theo câu mới:** khi bạn kéo lên đọc lại thì hiện nút "Mới nhất ↓". Cuối danh sách có dòng "● Đang nghe…".
- **Đánh dấu:** mỗi câu có nút đánh dấu để tìm lại sau.
- **Đọc to bản dịch:** bật/tắt bằng icon loa ở góc trên. Nên dùng tai nghe.
- **Viên ngôn ngữ ở góc trên** (ví dụ "Việt ⇄ Trung") chỉnh hai thứ:
  - phụ đề dịch sang tiếng gì;
  - phát biểu bằng tiếng gì (mặc định "Tự động": ngôn ngữ nghe thấy nhiều nhất gần đây).
- **Tạm dừng | Hoàn tất:** viên cam ở thanh dưới. Hoàn tất thì lưu vào Thư viện và tự tóm tắt.

### Phát biểu
- Bấm nút tròn **"Phát biểu"**, nói tiếng Việt, xong bấm **"Xong"**. App dịch sang tiếng của phía bên kia và **đọc to ra loa ngoài của điện thoại**, kể cả khi bạn đang đeo tai nghe.
- Bản dịch đọc riêng cho bạn vẫn vào tai nghe.
- Câu bạn phát biểu hiện trong phụ đề với nhãn cam "Bạn".
- Trong lúc bạn nói và lúc máy đang đọc, phiên dịch chính chỉ nhận im lặng, nên câu đó không bị dịch hai lần.

### Hiểu sâu hơn
- **Hỏi nhanh** (icon hội thoại ở góc trên): hỏi ngay trong cuộc họp, ví dụ "Họ vừa nói gì về giá?", "Còn chờ mình trả lời gì?". Câu trả lời kèm mốc giờ và được lưu cùng cuộc họp.
- **Giải thích:** chạm vào một câu để xem:
  - nghĩa thật của câu;
  - sắc thái (từ chối khéo, ép giá…);
  - 2–3 câu có thể đáp lại, viết bằng tiếng của người nói, có nút sao chép.

### Ngữ cảnh
- Nhập chủ đề và danh sách thuật ngữ (ví dụ `MOQ → số lượng tối thiểu`).
- **Lấy từ ảnh:** chụp báo giá, catalog, danh thiếp hay slide, AI tự điền chủ đề và tên riêng.
- Ngữ cảnh được dùng để:
  - dịch lại đúng thuật ngữ những câu đã xong trong cuộc họp;
  - nhận dạng và dịch tệp tải lên;
  - tóm tắt và hỏi đáp.

### Thư viện
- Mỗi mục có ba tab:
  - **Tóm tắt:** tổng quan, đã chốt, việc cần làm (ai, hạn nào), còn bỏ ngỏ.
  - **Bản ghi:** song ngữ, có giờ từng câu.
  - **Hỏi đáp:** câu trả lời kèm mốc giờ trong bản ghi.
- **Chia sẻ biên bản** qua Zalo, Messenger hay email: chỉ phần tóm tắt, hoặc kèm cả bản ghi song ngữ.
- **Tải âm thanh lên:** chọn tệp (m4a, mp3, wav…, tối đa 25 MB) để nhận dạng, dịch và tóm tắt.

### Cài đặt
- Khoá OpenAI: lưu trong bộ nhớ an toàn của máy, có kiểm tra khoá ngay khi lưu.
- Chất lượng dịch tệp và thuật ngữ: **Nhanh** hoặc **Kỹ hơn**.
- Chi phí ước tính của tháng, tính ngay trên máy.

## Cài đặt nhanh

1. Vào trang **Releases** của repo, tải file `scoai-voice-openai-<phiên bản>-arm64.apk` (dành cho điện thoại Android 64-bit, Android 7 trở lên).
2. Mở file APK trên điện thoại và cho phép "Cài ứng dụng không rõ nguồn" nếu máy hỏi.
3. Mở **SCOAI Voice**, vào **Cài đặt**, dán khoá OpenAI (`sk-…`), bấm **Lưu và kiểm tra**.
   - Tạo khoá tại [platform.openai.com](https://platform.openai.com) › API keys.
   - Tài khoản cần có tiền và được dùng `gpt-realtime-translate`.
4. Lần đầu bắt đầu cuộc họp, cho phép app dùng micro.

## Cách dùng

1. **Trang chủ → Bắt đầu cuộc họp.**
2. Ở màn chuẩn bị:
   - đặt tên cuộc họp (không bắt buộc);
   - chọn **Dịch sang** (thường là Tiếng Việt);
   - có thể **Thêm ngữ cảnh** (gõ tay hoặc chụp ảnh);
   - bật **Đọc to** nếu đeo tai nghe.
3. Bấm **Bắt đầu ghi âm**. Người khác nói tiếng gì cũng được, app tự nhận ra.
4. Muốn đáp lại: bấm **Phát biểu**, nói tiếng Việt, bấm **Xong**. Điện thoại đọc câu đó bằng tiếng của đối phương.
5. Không hiểu một câu: chạm vào câu đó để xem **Giải thích**. Cần tra lại nội dung: bấm icon **Hỏi nhanh**.
6. Bấm **Hoàn tất**. Cuộc họp được lưu và tự tóm tắt. Bấm nút chia sẻ để gửi biên bản.

## Chế độ thử (không cần khoá)

Dùng để thử mọi màn hình trên điện thoại thật mà không cần khoá OpenAI và không tốn tiền.
- **Cách bật:** Cài đặt › **Chế độ thử**, hoặc bấm **Dùng thử** trên banner ở Trang chủ khi chưa có khoá.
- **Cuộc họp:** micro và loa vẫn chạy thật, nhưng phụ đề là một kịch bản họp mẫu với nhà cung cấp, gồm câu tiếng Trung, tiếng Anh và một câu tiếng Việt. Kịch bản có đủ bản dịch, và mỗi câu dịch kèm một tiếng bíp ngắn để thử nút Đọc to.
- **Phát biểu:** bấm Phát biểu, nói khoảng một giây là có câu trả lời mẫu kèm một tiếng bíp dài. Cắm tai nghe để kiểm tra tiếng có ra loa ngoài không.
- **Hỏi nhanh, Giải thích, Tóm tắt, Lấy ngữ cảnh từ ảnh, Tải âm thanh lên** trả kết quả mẫu.
- **Thư viện** có thêm hai mục `[Mẫu]`: một cuộc họp đã có tóm tắt, hỏi đáp và câu đánh dấu, và một tệp tải lên chưa tóm tắt. Tắt Chế độ thử thì hai mục này tự xoá.
- Phần mẫu nằm ở `lib/demo/`. Nó trả lời theo đúng định dạng của OpenAI, nên code gọi API, ghép câu và xử lý kết quả của app đều chạy thật. Chế độ thử không tính vào chi phí ước tính.

## Model OpenAI và chi phí

Tên model và giá theo tài liệu của OpenAI ngày 13/11/2026.

| Việc | Model / endpoint | Giá niêm yết |
|---|---|---|
| Dịch trực tiếp | `gpt-realtime-translate`, WebSocket `/v1/realtime/translations` | 0,034 USD/phút âm thanh |
| Phát biểu | `gpt-realtime-translate`, phiên riêng, chỉ mở khi bạn nói | 0,034 USD/phút lúc mở |
| Phụ đề lời gốc | `gpt-realtime-whisper` (đặt trong phiên dịch) | chưa rõ có tính riêng không |
| Nhận dạng tệp | `gpt-transcribe`, `/v1/audio/transcriptions` | 0,0045 USD/phút |
| Dịch tệp, sửa thuật ngữ | `gpt-6-luna` (Nhanh) hoặc `gpt-6.1-terra` (Kỹ hơn), Responses API | 0,10/0,50 hoặc 1/5 USD cho 1 triệu token vào/ra |
| Tóm tắt, hỏi đáp, giải thích, đọc ảnh | `gpt-6.1-terra`, Responses API, JSON theo schema | 1/5 USD cho 1 triệu token vào/ra |

**Ước tính một giờ họp:**
- Dịch trực tiếp khoảng **2,04 USD**.
- Tóm tắt và vài câu hỏi thêm **0,05–0,15 USD**.
- Phát biểu tính theo số phút bạn nói.
- Bật hay tắt đọc to không đổi giá, vì model luôn trả kèm giọng đọc.

Tên model nằm trong `lib/openai/*.dart`, bảng giá dùng để ước tính nằm trong `lib/storage/settings_store.dart` (`Prices`).

## Khoá API và quyền riêng tư

- **Không có khoá nào trong mã nguồn hay git.** Người dùng tự nhập khoá trong app. Khoá được lưu bằng `flutter_secure_storage` (Android Keystore) và chỉ gửi tới OpenAI.
- `.gitignore` chặn sẵn `.env`, keystore và `key.properties`.
- App gọi thẳng OpenAI, không qua máy chủ trung gian. Cách này hợp khi mỗi người dùng một khoá riêng. Muốn phát app rộng rãi thì cần thêm một proxy nhỏ cấp client secret tạm thời (`POST /v1/realtime/translations/client_secrets`).
- Mọi lệnh gọi Responses API đều gửi `"store": false`.
- `android:allowBackup="false"`.
- Bản ghi, tóm tắt và hỏi đáp chỉ lưu trên máy, dạng JSON trong thư mục riêng của app. App không lưu âm thanh.

## Build từ mã nguồn

Cần có:
- Flutter 3.44 (Dart 3.12);
- Android SDK;
- JDK 17.

```bash
flutter pub get
flutter analyze
flutter test
flutter run                                     # chạy bản debug trên điện thoại đang cắm
flutter build apk --release --target-platform android-arm64
```

File APK nằm ở `build/app/outputs/flutter-apk/app-release.apk`. Bản release hiện được ký bằng khoá debug (cấu hình mặc định của Flutter), đủ để cài thử. Muốn đưa lên cửa hàng ứng dụng thì cần thêm khoá ký riêng trong `android/key.properties` (file này đã nằm trong `.gitignore`).

## Kiến trúc

```
lib/
  domain/      lang, records (dữ liệu Thư viện), segmenter (cắt câu, đoán ngôn ngữ),
               caption_assembler (ghép lời gốc ↔ bản dịch)
  openai/      realtime_translate (WebSocket dịch trực tiếp), responses_client, text_ai
               (dịch, tóm tắt, hỏi đáp, giải thích, đọc ảnh + prompt), transcribe_client
  live/        session_pipe (micro → phiên dịch, đệm khi mất mạng, xả phiên),
               meeting_controller (cuộc họp, Phát biểu, Hỏi nhanh), live_turn, audio_ports
  platform/    device_audio (micro điện thoại, loa, loa phòng, giữ màn hình sáng)
  storage/     library_store (JSON), key_store (Keystore), settings_store (cài đặt + chi phí)
  demo/        Chế độ thử: phiên dịch theo kịch bản, AI văn bản mẫu, mục Thư viện mẫu
  share/       minutes (văn bản biên bản để chia sẻ)
  ui/          home, meeting_setup, meeting, context, upload, saved, settings,
               captions (phụ đề), sheets (Giải thích, Hỏi nhanh), logo, theme
android/app/src/main/kotlin/com/scoai/voice/openai/
               MainActivity (kênh "scoai.voice/room_speaker"), RoomSpeaker (phát ra loa ngoài)
```

**Luồng của một cuộc họp:**

```
micro điện thoại ──► SessionPipe ──► gpt-realtime-translate (WebSocket)
                                       ├─ lời gốc  ─┐
                                       ├─ bản dịch ─┴─► CaptionAssembler ──► phụ đề song ngữ
                                       └─ giọng dịch ─► tai nghe (nếu bật Đọc to)
nút Phát biểu ──► phiên dịch thứ hai ──► giọng dịch ──► RoomSpeaker (loa ngoài)
Hoàn tất ──► Thư viện (JSON) ──► gpt-6.1-terra: tóm tắt, hỏi đáp
```

**Một số chi tiết quan trọng:**
- **Ghép câu.** Phiên dịch trả về hai luồng chữ nối đuôi nhau, lời gốc và bản dịch, nhưng không báo khi nào hết câu và không có id nối câu dịch với câu gốc. `CaptionAssembler` tự ghép:
  - cắt cả hai luồng theo dấu câu;
  - câu đã đúng ngôn ngữ đích đứng riêng;
  - các câu còn lại ghép theo thứ tự;
  - mỗi lần cả hai luồng cùng im khoảng 2,5 giây thì phần còn thừa được gộp vào câu cuối, nên nếu có ghép lệch thì cũng không kéo dài quá một quãng ngừng.
- **Âm thanh liên tục.** OpenAI yêu cầu gửi âm thanh liên tục, kể cả im lặng, suốt khi phiên mở. Tạm dừng thì app gửi thêm chút im lặng để model dịch nốt câu cuối rồi đóng phiên; Tiếp tục thì mở phiên mới.
- **Phiên dài.** App tự chuyển sang phiên mới ở phút thứ 50, vì phiên realtime giới hạn 60 phút.
- **Mất mạng.** App thử nối lại tối đa 3 lần và giữ tạm tối đa 15 giây âm thanh trong lúc chờ.
- **Thuật ngữ.** Phiên dịch realtime không nhận danh sách thuật ngữ. Vì vậy câu đã xong mà có chứa thuật ngữ trong Ngữ cảnh sẽ được dịch lại bằng `gpt-6-luna` kèm danh sách thuật ngữ.
- **Loa phòng.** `RoomSpeaker.kt` xin Android dùng loa trong của máy cho riêng luồng Phát biểu. Nếu Android vẫn đưa tiếng sang chỗ khác, từ câu sau app chuyển sang luồng chuông báo, vốn luôn phát ra loa.
- **Micro.** Cuộc họp luôn thu bằng micro của điện thoại, không dùng micro trên tai nghe.

## Kiểm thử

```bash
flutter analyze
flutter test
```

75 test, chạy hoàn toàn bằng WebSocket và HTTP giả, không gọi OpenAI thật:
- `test/openai/`:
  - gói tin `session.update`;
  - âm thanh cắt khúc 200 ms dạng base64;
  - các sự kiện từ server, mất kết nối, đóng phiên;
  - body Responses API (`json_schema` strict, `store:false`);
  - lỗi 401/429 không làm lộ khoá;
  - multipart của `gpt-transcribe` và giới hạn 25 MB;
  - Giải thích, ảnh gửi dạng `input_image`, văn bản biên bản.
- `test/domain/`: cắt câu (số thập phân, dấu câu tiếng Trung) và ghép câu (câu đúng ngôn ngữ đích, model gộp câu, bản dịch đến trễ).
- `test/live/`:
  - từ micro tới phiên dịch rồi ra câu;
  - đọc to;
  - tạm dừng / tiếp tục và mốc giờ;
  - lưu Thư viện;
  - nối lại khi mất mạng, chuyển phiên;
  - đổi ngôn ngữ, sửa thuật ngữ;
  - Phát biểu (phiên riêng, ra loa phòng, phiên chính chỉ nhận im lặng);
  - Hỏi nhanh.
- `test/demo/`: Chế độ thử (kịch bản họp qua client thật, Phát biểu ra loa phòng, AI văn bản mẫu, bật/tắt dữ liệu mẫu).
- `test/storage/`: Thư viện JSON, chặn id không an toàn, tính chi phí.
- `test/ui/`: màn họp (phụ đề, Cả hai/Gốc/Dịch, "Đang dịch…", đánh dấu, loa, lọc, Phát biểu, viên ngôn ngữ).

## Giới hạn và việc chưa làm

- **Chưa thử trên điện thoại thật với OpenAI thật.** Định dạng gói tin lấy từ tài liệu OpenAI ngày 13/11/2026.
- **Mã ngôn ngữ:** tài liệu OpenAI chỉ có ví dụ `"es"`/`"fr"`; chưa kiểm chứng `vi`, `zh`, `en` cho `audio.output.language`.
- **Độ trễ thực tế** và chất lượng ghép câu với giọng nói thật chưa đo.
- **Phát biểu ra loa ngoài khi đeo tai nghe** chưa thử trên máy thật. Vài máy hoặc tai nghe Bluetooth có thể không cho tách đường âm thanh; khi đó app dùng luồng chuông báo, nên âm lượng theo mức chuông báo.
- **Ghi nền:** chưa có foreground service, nên tắt màn hình hoặc chuyển app thì Android có thể ngắt micro. Trong lúc họp, app giữ màn hình luôn sáng.
- **Tệp tải lên:** tối đa 25 MB, chưa tự cắt tệp dài. `gpt-transcribe` không trả mốc giờ, nên Bản ghi của tệp đánh số câu.
- **Ngôn ngữ:** hiện có Việt, Trung, Anh. Thêm ngôn ngữ khác cần cách nhận diện ngôn ngữ cho từng câu.
- **Chưa có:** chế độ tối, xuất file bản ghi, tìm kiếm trong bản ghi, nghe lại âm thanh gốc, bản iOS.
- **Đã bỏ:** màn Hội thoại (hai nút "Tôi nói" / "Người kia nói"), vì trùng với Phát biểu. Mục hội thoại đã lưu từ trước vẫn mở được.
