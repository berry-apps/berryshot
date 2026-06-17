# Hướng dẫn Build và Chạy thử (BerryShot)

Ứng dụng này được xây dựng bằng **Swift 6** và **Swift Package Manager**. Do tính chất của một ứng dụng macOS native, quá trình build và chạy được thực hiện hoàn toàn qua Terminal hoặc Xcode.

## Yêu cầu hệ thống
- **macOS 14.0** trở lên (bắt buộc cho ScreenCaptureKit và các tính năng SwiftUI mới).
- **Xcode 15.0+** hoặc Command Line Tools có hỗ trợ Swift 6.

---

## 1. Build ứng dụng

Bạn có thể build ứng dụng thông qua Terminal bằng công cụ `swift build`.

Mở Terminal, di chuyển vào thư mục gốc của dự án (`/Users/tan/idea/screenshot`) và chạy lệnh:

```bash
swift build
```

Quá trình này sẽ tải các dependencies (nếu có) và biên dịch mã nguồn. Lần đầu tiên có thể mất một chút thời gian. Nếu thành công, bạn sẽ thấy thông báo `Build complete!`.

---

## 2. Chạy ứng dụng

Bạn có thể chạy ứng dụng trực tiếp từ Terminal bằng lệnh:

```bash
swift run
```

Hoặc chạy file thực thi đã được biên dịch (tuỳ thuộc vào kiến trúc chip CPU của bạn, ví dụ ARM64):

```bash
.build/arm64-apple-macosx/debug/BerryShot
```

### ⚠️ Lưu ý cấp quyền:
Khi ứng dụng khởi chạy lần đầu tiên và bạn sử dụng phím tắt chụp màn hình (mặc định là `⌘ + Shift + 1`), macOS sẽ yêu cầu **Quyền Ghi hình Màn hình (Screen Recording)**. 
1. Mở **System Settings** (Cài đặt hệ thống) > **Privacy & Security** (Quyền riêng tư & Bảo mật).
2. Kéo xuống mục **Screen Recording** (Ghi hình màn hình).
3. Bật công tắc cho Terminal hoặc ứng dụng BerryShot.
4. Khởi động lại ứng dụng nếu cần.

---

## 3. Cách sử dụng (Test luồng cơ bản)

1. **Khởi chạy ứng dụng**: Sau khi chạy `swift run`, bạn sẽ thấy một biểu tượng (icon máy ảnh) xuất hiện trên thanh Menu Bar (góc trên bên phải màn hình).
2. **Kích hoạt chụp màn hình**: 
   - Cách 1: Bấm vào biểu tượng trên Menu Bar và chọn **"Capture Region"**.
   - Cách 2: Bấm tổ hợp phím tắt **`Command + Shift + 1`**.
3. **Thao tác Overlay**: 
   - Màn hình sẽ được làm mờ (dark overlay).
   - Dùng chuột **kéo thả** để chọn một vùng (Region). 
   - Sau khi nhả chuột ra, bạn có thể thử vẽ (annotation mode) lên vùng vừa chọn.
4. **Lưu trữ & OCR**:
   - Sau khi hoàn thành thao tác, ảnh sẽ tự động được cắt và lưu vào máy. OCR chạy ngầm sẽ trích xuất chữ.
   - Các file lưu tại: `~/Library/Application Support/BerryShot/` (bạn có thể mở thư mục này để kiểm tra ảnh đã chụp).

---

## 4. Chạy Unit Test

Để đảm bảo các module hoạt động chính xác (OCR, History, Storage...), chạy lệnh:

```bash
swift test
```
Hệ thống sẽ chạy toàn bộ các test cases nằm trong thư mục `Tests/`.
