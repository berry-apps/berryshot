Để đưa trang web `notex.work` đạt điểm tuyệt đối (100/100) trên cả Mobile và Desktop dựa trên báo cáo PageSpeed Insights hiện tại, bạn cần tập trung xử lý các vấn đề cốt lõi sau đây.

Hiện tại, trang của bạn có điểm số rất tốt ở mảng SEO (100) và Best Practices (96), nhưng cần cải thiện ở **Performance (67)**, **Accessibility (86)** và **Agentic Browsing (1/3)**. Do cấu hình phần cứng giả lập của Mobile (mạng 4G chậm, CPU yếu) khắt khe hơn Desktop, nên khi bạn tối ưu triệt để cho Mobile, điểm số trên Desktop sẽ tự động đạt mức tuyệt đối.

Dưới đây là các bước hành động cụ thể:

---

## 1. Nâng cấp Performance (Hiệu năng) từ 67 lên 100

Vấn đề lớn nhất khiến điểm số bị kéo xuống là thời gian tải luồng chính bị nghẽn (Chỉ số LCP lên tới 6.8 giây trên Mobile).

* **Tối ưu hóa hình ảnh (Tiết kiệm ~750 KB):**
* **Thay đổi định dạng:** Ảnh `AppIcon.png` và ảnh QR từ `vietqr.io` đang dùng định dạng cũ (.png). Hãy chuyển toàn bộ sang định dạng hiện đại như **WebP** hoặc **AVIF** để giảm dung lượng file xuống từ 50% - 80% mà không giảm chất lượng.
* **Nén kích thước thực tế:** Ảnh `AppIcon.png` có kích thước gốc là $1024 \times 1024$ pixel nhưng hiển thị thực tế trên màn hình chỉ có $70 \times 70$ pixel. Việc bắt trình duyệt tải một file ảnh khổng lồ rồi co nhỏ lại là lý do chính khiến trang bị chậm. Hãy resize ảnh gốc về đúng kích thước hiển thị lớn nhất cần thiết (ví dụ: $140 \times 140$ pixel cho màn hình Retina).


* **Xử lý tài nguyên chặn hiển thị (Render-blocking) (Tiết kiệm ~2.4 giây):**
* **Tải CSS có điều kiện:** Trình giữ chỗ Tailwind CSS (`cdn.tailwindcss.com`) tốn 770ms để tải và chặn render. Trong môi trường production, bạn không nên dùng CDN script này trực tiếp. Hãy build mã nguồn bằng CLI của Tailwind để loại bỏ các class thừa (Purge CSS) và nhúng file CSS đã được tối ưu, minify trực tiếp vào thẻ `<head>`.
* **Trì hoãn Google Fonts:** Hãy thêm thuộc tính `display=swap` vào link Google Fonts để trình duyệt hiển thị font hệ thống trước trong lúc chờ tải font chữ custom, tránh làm chậm chỉ số FCP và LCP.


* **Khắc phục lỗi Animation không được tối ưu (Non-composited animations):**
* Phần tử con trỏ tự động (`div#sim-auto-cursor`) đang sử dụng các thuộc tính CSS `top` và `left` để làm chuyển động. Việc này ép trình duyệt phải tính toán lại bố cục liên tục (Forced reflow mất 80ms). Hãy thay thế bằng thuộc tính `transform: translate(x, y)` để đẩy việc xử lý cho GPU, giúp animation mượt mà và không gây lag luồng chính.


* **Cấu hình Bộ nhớ đệm (Cache Policy):**
* Ảnh QR từ `vietqr.io` và `api.qrserver.com` hiện không thiết lập thời gian lưu cache (Cache TTL). Hãy cấu hình header `Cache-Control` cho các tài nguyên tĩnh tối thiểu là 6 tháng hoặc 1 năm.



---

## 2. Nâng cấp Accessibility (Khả năng tiếp cận) từ 86 lên 100

Đạt điểm tuyệt đối phần này giúp người khuyết tật (sử dụng trình đọc màn hình - Screen Reader) dễ dàng tiếp cận website của bạn.

* **Bổ sung tên hiển thị cho nút bấm (Accessible Name):**
* Nút đóng trình mô phỏng AI (`button.text-slate-500` có hàm `onclick="closeSimulatorAI()"`) hiện chỉ có icon mà không có text. Trình đọc màn hình sẽ chỉ đọc lên là "button" khiến người khiếm thị không hiểu nút này làm gì.
* **Cách sửa:** Thêm thuộc tính `aria-label="Đóng trình mô phỏng AI"` vào thẻ `<button>` đó.


* **Sửa lỗi tương phản màu sắc (Color Contrast):**
* Một số phần văn bản màu xám trên nền tối (như phần text `support@notex.work`, thẻ span `Free & Offline Secure`, chữ `BERRYSHOT INTERFACE`...) có tỷ lệ tương phản quá thấp, rất khó đọc cho người có thị lực kém.
* **Cách sửa:** Thay đổi mã màu chữ (text color) sáng hơn hoặc làm nền tối hơn để đạt tỷ lệ tương phản tối thiểu là $4.5:1$.


* **Sắp xếp lại thứ tự thẻ tiêu đề (Heading Order):**
* Cấu trúc tiêu đề của bạn đang bị nhảy bậc (Ví dụ: Thẻ `<h4>` xuất hiện trước hoặc bỏ qua `<h2>`, `<h3>`). Hãy đảm bảo các thẻ tiêu đề tuân theo thứ tự phân cấp nghiêm ngặt từ `<h1>` đến `<h6>`.



---

## 3. Tối ưu hóa Agentic Browsing (Dành cho AI Agents) từ 1/3 lên tuyệt đối

Đây là tiêu chuẩn mới để các mô hình ngôn ngữ lớn (LLM) và AI Agent có thể cào dữ liệu và hiểu trang web của bạn một cách chính xác nhất.

* **Sửa file `llms.txt`:**
* Hệ thống báo lỗi file `llms.txt` của bạn đang thiếu thẻ tiêu đề chính (H1 header). Hãy mở file này ra và thêm dòng tiêu đề dạng `# Tên Dự Án Của Bạn` ở ngay đầu file.
* Đồng thời bổ sung thêm các link dẫn (liên kết) liên quan đến tài liệu hoặc các trang con bên trong file Markdown này để AI có thể điều hướng theo luồng.


* **Đồng bộ Text cho nút bấm:**
* Việc sửa lỗi thêm `aria-label` cho nút `closeSimulatorAI()` ở phần Accessibility phía trên cũng sẽ tự động giải quyết lỗi *"Buttons must have discernible text"* ở phần Agentic Browsing này.



Khi bạn hoàn thành việc thay thế script Tailwind CDN bằng file CSS đã build, nén lại kích thước ảnh `AppIcon`, bổ sung thuộc tính `aria-label` và sửa cấu trúc file `llms.txt`, trang web của bạn chắc chắn sẽ chạm mốc 100 điểm tuyệt đối trên cả hai nền tảng.