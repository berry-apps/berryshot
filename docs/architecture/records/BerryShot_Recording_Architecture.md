# BerryShot Recording Architecture vNext

## Mục tiêu

Mở rộng BerryShot từ Screenshot + Annotation thành:

- Screenshot + Annotation (đã có)
- Screen Recording
- Live Annotation During Recording
- System Audio Recording
- Microphone Recording
- Multi-track Audio
- Future AI Transcript / Meeting Summary

---

## Kiến trúc hiện tại

BerryShot hiện đã có:

- OverlayWindow
- OverlayViewModel
- AnnotationEngine
- OverlayView

Annotation layer đã hoạt động độc lập với màn hình gốc.

Đây là lợi thế lớn vì có thể tái sử dụng toàn bộ engine hiện tại cho Recording Mode.

---

## Kiến trúc đề xuất

```text
Desktop Screen
        │
        ▼
ScreenCaptureKit
        │
        ├── Video Stream
        ├── System Audio Stream
        └── Microphone Stream

Annotation Engine
(Existing BerryShot Engine)
        │
        ▼
Annotation Layer Stream

                ▼
        Recording Composer
                │
                ├── Video Track
                ├── Annotation Track
                ├── System Audio Track
                └── Mic Audio Track

                ▼
            AVAssetWriter
                │
                ▼
          MOV / MP4 Output
```

---

## Nguyên nhân QuickTime không thu được tiếng người bên kia khi đeo tai nghe

### Hiện tượng

Google Meet:

- User A nói
- User B nghe qua AirPods

QuickTime Screen Recording:

- Thu được microphone của User B
- Không thu được âm thanh phát ra từ Google Meet

### Nguyên nhân kỹ thuật

macOS tách:

```text
Input Device
    └─ Microphone

Output Device
    └─ AirPods
```

QuickTime mặc định:

```text
Screen Video
+
Microphone Input
```

Nó KHÔNG capture:

```text
System Audio Output
```

Do đó:

```text
Người khác nói
      ↓
Google Meet
      ↓
AirPods
```

âm thanh chỉ được phát ra thiết bị output và không đi vào file ghi hình.

Đây là lý do người dùng thường phải cài:

- BlackHole
- SoundFlower
- Loopback

để tạo Virtual Audio Device.

---

## Cách BerryShot xử lý

Không dùng Virtual Audio Driver.

Sử dụng ScreenCaptureKit.

```swift
capturesAudio = true
captureMicrophone = true
```

BerryShot lấy:

```text
System Audio Stream
```

trực tiếp từ hệ điều hành trước khi âm thanh được gửi tới:

- AirPods
- Bluetooth Headset
- USB Headset
- Built-in Speaker

Do đó dù người dùng đeo tai nghe vẫn thu được:

- Tiếng người bên kia
- Tiếng microphone

đồng thời.

---

## Case bắt buộc phải support

### AirPods

```text
Meet Audio → AirPods
Mic → AirPods Mic
```

Record đầy đủ.

### Bluetooth Headset

Record đầy đủ.

### USB Headset

Record đầy đủ.

### Wired Headset

Record đầy đủ.

### External Audio Interface

Record đầy đủ.

### User đổi tai nghe giữa chừng

BerryShot phải:

- theo dõi route change
- tự động reconnect audio stream
- không làm hỏng recording

---

## Thành phần mới

### RecordingManager

Quản lý:

- start recording
- stop recording
- pause
- resume

### ScreenCaptureService

Wrapper cho ScreenCaptureKit.

Trả về:

- video frame
- system audio
- microphone audio

### AnnotationRecordingService

Thu toàn bộ event:

- arrow
- rectangle
- circle
- text
- pencil
- blur

kèm timestamp.

### AudioMixerService

Quản lý:

- system volume
- mic volume
- mute mic
- mute system

### ExportService

Xuất:

- mov
- mp4

---

## Live Annotation Recording

Điểm khác biệt chính của BerryShot.

### Thay vì

```text
Record Screen
```

### BerryShot

```text
Record Screen
+
Record Annotation
```

Ví dụ:

00:05 vẽ mũi tên

00:08 khoanh vùng bug

00:15 blur mật khẩu

00:20 thêm text

Tất cả xuất hiện realtime trong video.

---

## Kiến trúc Annotation Recording

Không nên burn trực tiếp vào video.

Lưu event.

Ví dụ:

```json
{
  "time": 8.4,
  "tool": "arrow",
  "from": [100,100],
  "to": [300,300]
}
```

Ưu điểm:

- sửa annotation sau khi quay
- đổi màu
- xóa annotation
- animation đẹp hơn

---

## Multi-track Audio

Khuyến nghị lưu:

Track 1:
System Audio

Track 2:
Microphone

Track 3:
Video

Track 4:
Annotation Metadata

Lợi ích:

- AI transcript tốt hơn
- speaker separation
- chỉnh volume từng nguồn

---

## Roadmap

### Phase 1

- Full Screen Recording
- Window Recording
- Region Recording
- System Audio
- Microphone
- Live Annotation

### Phase 2

- Webcam Overlay
- Pause Resume
- Multi-track Export
- Annotation Timeline

### Phase 3

- Transcript
- AI Summary
- AI Step Extraction
- AI Documentation Generation

