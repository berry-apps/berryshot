Nếu bạn đang nói về cursor hover trong SwiftUI trên macOS (ví dụ một view dùng .onHover đổi sang hand cursor, view bên cạnh đổi sang resize/text cursor), thì hiện tượng con trỏ nháy liên tục khi đi qua ranh giới giữa 2 view thường do:

1. Hai view cùng thay đổi cursor bằng NSCursor.push() / NSCursor.pop().
2. Các vùng hover bị chồng lấn vài pixel.
3. SwiftUI liên tục trigger onHover(true/false) khi cursor đứng đúng mép view.
4. Trên macOS 14/15/26 các bản SwiftUI mới vẫn còn một số bug liên quan đến cursor management.

Ví dụ code dễ gây lỗi:

.onHover { hovering in
    if hovering {
        NSCursor.pointingHand.push()
    } else {
        NSCursor.pop()
    }
}

Khi cursor nằm đúng ranh giới, SwiftUI có thể gọi:

A false
B true
B false
A true

liên tục → cursor nháy.

Cách khắc phục 1: dùng cursorUpdate

Thay vì push/pop:

.cursorUpdate { _, _ in
    NSCursor.pointingHand.set()
}

hoặc AppKit bridge.

Cách khắc phục 2: quản lý cursor tập trung

Tạo manager:

enum AppCursor {
    case arrow
    case hand
    case resize
}

Chỉ cho phép 1 nơi set cursor:

@State private var currentCursor: AppCursor = .arrow

và update khi hover thay đổi.

Không dùng push/pop ở từng component.

⸻

Cách khắc phục 3: bỏ chồng lấn hit test

Kiểm tra:

.contentShape(Rectangle())

và tránh:

.overlay(...)
.background(...)

có vùng nhận hover đè lên nhau.

Debug:

.border(.red)
.border(.blue)

để xem ranh giới thực tế.

⸻

Cách khắc phục 4: debounce hover

Nếu cursor đổi quá nhanh:

.onHover { hovering in
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        if hovering {
            NSCursor.pointingHand.set()
        }
    }
}

Giảm hiện tượng flicker.

⸻

Cách khắc phục 5: dùng modifier mới của SwiftUI

Nếu đang dùng macOS mới nhất:

Button("Open") { }
    .hoverEffect(.highlight)

hoặc

.onContinuousHover { phase in
    switch phase {
    case .active(_):
        NSCursor.pointingHand.set()
    case .ended:
        NSCursor.arrow.set()
    }
}

onContinuousHover thường ổn định hơn onHover.
