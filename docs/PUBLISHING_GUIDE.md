# Hướng dẫn Đóng gói, Ký (Code Signing), Công chứng (Notarization) và Đưa App lên Store

Tài liệu này hướng dẫn chi tiết các bước để triển khai BerryShot khi bạn đã có tài khoản Apple Developer. Có 2 chiến lược phân phối chính trên macOS:
1. **Phân phối ngoài (Website/DMG)**: Yêu cầu Ký (Signing) và Công chứng (Notarization) với Apple để người dùng tải về không bị Gatekeeper báo lỗi bảo mật và chặn. Đồng thời giải quyết triệt để lỗi hỏi quyền Screen Capture liên tục.
2. **Phân phối qua Mac App Store (MAS)**: Yêu cầu đóng gói bằng App Sandbox và đẩy lên App Store Connect.

---

## BƯỚC 1: CHUẨN BỊ CHỨNG CHỈ (CERTIFICATES) TRÊN MÁY DEV

1. Mở **Xcode**.
2. Vào **Xcode > Settings (Preferences) > Accounts**.
3. Bấm dấu **+** ở góc dưới bên trái, chọn **Apple ID** và đăng nhập bằng tài khoản Apple Developer bạn mới mượn được.
4. Chọn Team của bạn ở danh sách bên phải, bấm **Manage Certificates...**
5. Bạn cần nhấn dấu **+** và tạo các loại chứng chỉ sau (nếu chưa có):
   - **Developer ID Application**: Dành cho việc ký app phân phối ngoài (DMG).
   - **Apple Distribution**: Dành cho việc ký app đẩy lên Mac App Store.

---

## CHIẾN LƯỢC A: PHÂN PHỐI NGOÀI QUA FILE DMG (Khuyên dùng trước)

Phân phối ngoài giúp app không bị gò bó bởi các luật lệ nghiêm ngặt của App Store (đặc biệt là App Sandbox vốn rất hay chặn các tính năng Global Hotkey và Screen Capture).

### 1. Cập nhật script `build_app.sh`
Mở script `build_app.sh` và tìm dòng:
```bash
codesign --force --deep --sign - "$APP_DIR"


```
Thay thế nó bằng ID chứng chỉ của bạn. (Bạn có thể mở Keychain Access > My Certificates để copy tên chứng chỉ Developer ID). Cú pháp như sau:
```bash
# Ví dụ: "Developer ID Application: Nguyen Van A (12345ABCDE)"
SIGNING_IDENTITY="Developer ID Application: Vu Dong (WZ2Z528AM6)"

echo "Ký ứng dụng bằng Developer ID..."
codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_DIR"
```
*Lưu ý: Phải thêm cờ `--options runtime` để bật Hardened Runtime (Bắt buộc nếu muốn Apple cấp phép Notarization).*

### 2. Tiến hành Notarize (Công chứng với Apple)
Notarization là quá trình gửi app của bạn lên server Apple quét mã độc. Nếu pass, Apple sẽ cấp 1 vé (ticket) hợp lệ. 

Để Notarize, bạn cần lấy **App-Specific Password** bằng cách vào trang [appleid.apple.com](https://appleid.apple.com). Sau đó chạy các lệnh sau trong Terminal sau khi build xong file ZIP:

```bash
# 1. Gửi file DMG lên Apple quét mã độc (Có thể mất 2-5 phút)
xcrun notarytool submit landingpage/assets/BerryShot.dmg \
    --apple-id "EMAIL_APPLE_ID_CỦA_BAN" \
    --password "APP_SPECIFIC_PASSWORD" \
    --team-id "TEAM_ID_CỦA_BAN" \
    --wait

# 2. Sau khi Terminal báo "Accepted", ta tiến hành "ghim" vé chứng nhận vào file DMG
xcrun stapler staple landingpage/assets/BerryShot.dmg
```

### 3. Hoàn tất
File DMG của bạn hiện đã an toàn tuyệt đối 100%. Gatekeeper của macOS sẽ không báo lỗi, và Quyền Screen Capture sẽ được lưu lại vĩnh viễn trên máy người dùng.

---

## CHIẾN LƯỢC B: ĐƯA LÊN MAC APP STORE (MAS)

Việc đưa app lên Mac App Store phức tạp hơn vì Apple bắt buộc app phải chạy trong "App Sandbox" (Môi trường cách ly hoàn toàn).

### 1. Tạo file Entitlements cho Sandbox
Bạn cần tạo một file tên là `BerryShot.entitlements` ở thư mục dự án với nội dung:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Bật App Sandbox -->
    <key>com.apple.security.app-sandbox</key>
    <true/>
    
    <!-- Cho phép kết nối mạng (để gửi ảnh lên server / gọi API AI) -->
    <key>com.apple.security.network.client</key>
    <true/>
    
    <!-- Cho phép truy cập tính năng ghi màn hình (ScreenCaptureKit) -->
    <key>com.apple.security.device.screen-recording</key>
    <true/>
</dict>
</plist>
```

### 2. Tạo App ID và App trên App Store Connect
1. Truy cập [developer.apple.com](https://developer.apple.com), vào phần **Certificates, Identifiers & Profiles**.
2. Tạo một **Identifier (App ID)** có Bundle ID là `com.tan.berryshot`.
3. Truy cập [appstoreconnect.apple.com](https://appstoreconnect.apple.com), tạo New App và chọn App ID vừa tạo.

### 3. Cấu hình Xcode & Build Archive
Với dự án dùng Swift Package Manager (như của chúng ta), cách tốt nhất để lên Store là dùng giao diện của Xcode.
1. Mở Finder, kéo thư mục `screenshot` (chứa Package.swift) thả vào icon Xcode để mở.
2. Tại Xcode, bấm vào tên Project ở thanh bar trên cùng, chuyển tab qua **Signing & Capabilities**.
3. Tick chọn **Automatically manage signing**. Chọn Team của bạn.
4. Bấm dấu **+ Capability** và thêm **App Sandbox**.
5. Chọn thiết bị build là **Any Mac (Apple Silicon, Intel)**.
6. Trên thanh Menu Xcode: Chọn **Product > Archive**.
7. Đợi Xcode build xong, cửa sổ **Organizer** sẽ hiện ra. Chọn bản Archive vừa build và bấm nút **Distribute App**.
8. Chọn **App Store Connect** và Xcode sẽ tự động làm mọi việc từ Ký (Sign), Đóng gói và Upload thẳng lên cho Apple duyệt.

### 4. Lưu ý quan trọng khi Review App Store
- **Global Hotkeys**: Việc dùng `RegisterEventHotKey` đôi khi sẽ bị Apple review làm khó vì nó yêu cầu quyền Accessibility ngoài Sandbox. Bạn có thể phải giải thích rõ với đội Review lý do cần phím tắt này.
- **Privacy Policy**: Bạn bắt buộc phải có một trang web chứa Privacy Policy (Chính sách bảo mật) liệt kê rõ app lấy ảnh màn hình của người dùng nhưng không gửi lung tung mà gửi đi đâu (Google Drive, OpenAI API). Trang `landingpage` của bạn cần bổ sung 1 đường link dẫn tới Privacy Policy này để dán vào App Store Connect.
