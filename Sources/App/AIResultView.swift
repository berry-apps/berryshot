import SwiftUI

public struct AIResultView: View {
    @ObservedObject var viewModel: AIResultViewModel
    var onClose: () -> Void
    @State private var isHoveringContent = false
    @State private var showCopiedToast = false
    @State private var isCloseHovered = false
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Drag Bar with Close Button
            ZStack {
                HStack {
                    Button(action: {
                        onClose()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.95, green: 0.36, blue: 0.34))
                                .frame(width: 12, height: 12)
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.black.opacity(0.6))
                                .opacity(isCloseHovered ? 1.0 : 0.0)
                        }
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .onHover { hover in
                        isCloseHovered = hover
                    }
                    .padding(.leading, 6)
                    
                    Spacer()
                    
                    // Copy Button
                    if !viewModel.resultText.isEmpty && viewModel.errorMessage == nil {
                        Button(action: {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(viewModel.resultText, forType: .string)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { showCopiedToast = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation(.easeOut(duration: 0.2)) { showCopiedToast = false }
                            }
                        }) {
                            Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(showCopiedToast ? .green : .white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                        .help("Copy content")
                    }
                }
                
                Text("AI Vision")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(height: 32)
            .background(Color.white.opacity(0.05))
            
            Divider().background(Color.white.opacity(0.1))
            
            // Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = viewModel.errorMessage {
                        VStack(spacing: 12) {
                            Spacer().frame(height: 60)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.red)
                            Text("Oops, something went wrong.")
                                .font(.headline)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                            Spacer()
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                    } else {
                        if viewModel.resultText.isEmpty && viewModel.isLoading {
                            // Prominent skeleton loading state when empty
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.purple)
                                    Text("Thinking...")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(.bottom, 8)
                                
                                SkeletonView()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                NativeMarkdownView(text: viewModel.resultText)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 20)
                                    .padding(.bottom, 20)
                                
                                // Thinking indicator streams immediately
                                if viewModel.isLoading {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Thinking...")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.bottom, 20)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHoveringContent = hovering
                }
            }
        }
        .frame(width: 400, height: 500)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}

public class AIResultViewModel: ObservableObject {
    @Published public var isLoading: Bool = true
    @Published public var resultText: String = ""
    @Published public var errorMessage: String? = nil
    
    public init() {}
}

struct SkeletonView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonLine(width: 320)
            SkeletonLine(width: 280)
            SkeletonLine(width: 300)
            SkeletonLine(width: 200)
        }
        .opacity(phase == 1 ? 0.3 : 0.8)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}

struct SkeletonLine: View {
    let width: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.15))
            .frame(width: width, height: 14)
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var isHovered = false
    @State private var showCopiedToast = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                HStack {
                    Text(language.lowercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.3))
            }
            
            ZStack(alignment: .topTrailing) {
                Text(code.isEmpty ? " " : code)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(red: 0.8, green: 0.9, blue: 1.0)) // soft blueish for code
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if isHovered {
                    Button(action: {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(code, forType: .string)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { showCopiedToast = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation(.easeOut(duration: 0.2)) { showCopiedToast = false }
                        }
                    }) {
                        Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(showCopiedToast ? .green : .white.opacity(0.7))
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help("Copy code")
                }
            }
        }
        .background(Color.black.opacity(0.4))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct NativeMarkdownView: View {
    let text: String
    
    var body: some View {
        let blocks = parseMarkdownBlocks(text)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let content):
                    headingView(level: level, content: content)
                case .codeBlock(let language, let code):
                    CodeBlockView(language: language, code: code)
                case .bulletList(let items):
                    bulletListView(items: items)
                case .paragraph(let content):
                    paragraphView(content: content)
                case .horizontalRule:
                    Divider()
                        .background(Color.white.opacity(0.2))
                        .padding(.vertical, 4)
                }
            }
        }
    }
    
    enum MarkdownBlock {
        case heading(level: Int, content: String)
        case codeBlock(language: String, code: String)
        case bulletList(items: [String])
        case paragraph(content: String)
        case horizontalRule
    }
    
    func parseMarkdownBlocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: .newlines)
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Empty line — skip
            if trimmed.isEmpty {
                i += 1
                continue
            }
            
            // Horizontal rule
            if trimmed.range(of: #"^[-*_]{3,}$"#, options: .regularExpression) != nil {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }
            
            // Heading
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let content = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                if !content.isEmpty {
                    blocks.append(.heading(level: min(level, 4), content: content))
                }
                i += 1
                continue
            }
            
            // Code block
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: lang, code: codeLines.joined(separator: "\n").trimmingCharacters(in: .newlines)))
                continue
            }
            
            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("- ") || l.hasPrefix("* ") || l.hasPrefix("• ") {
                        items.append(String(l.dropFirst(2)))
                        i += 1
                    } else if l.hasPrefix("  ") || l.hasPrefix("\t") {
                        // Continuation of list item
                        if !items.isEmpty {
                            items[items.count - 1] += " " + l
                        }
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items: items))
                continue
            }
            
            // Numbered list
            if trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if let m = l.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                        items.append(String(l[m.upperBound...]))
                        i += 1
                    } else if l.hasPrefix("  ") || l.hasPrefix("\t") {
                        if !items.isEmpty {
                            items[items.count - 1] += " " + l
                        }
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items: items))
                continue
            }
            
            // Regular paragraph — collect consecutive non-empty lines
            var paraLines: [String] = []
            while i < lines.count {
                let l = lines[i].trimmingCharacters(in: .whitespaces)
                if l.isEmpty || l.hasPrefix("#") || l.hasPrefix("```") || l.hasPrefix("- ") || l.hasPrefix("* ") {
                    break
                }
                paraLines.append(l)
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(content: paraLines.joined(separator: " ")))
            }
        }
        
        return blocks
    }
    
    @ViewBuilder
    func headingView(level: Int, content: String) -> some View {
        let attrString = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        Group {
            switch level {
            case 1:
                Text(attrString ?? AttributedString(content))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            case 2:
                Text(attrString ?? AttributedString(content))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
            case 3:
                Text(attrString ?? AttributedString(content))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            default:
                Text(attrString ?? AttributedString(content))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .textSelection(.enabled)
    }
    
    @ViewBuilder
    func bulletListView(items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.purple.opacity(0.8))
                        .frame(width: 12)
                    let attrString = try? AttributedString(markdown: item, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
                    Text(attrString ?? AttributedString(item))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    @ViewBuilder
    func paragraphView(content: String) -> some View {
        if let attrString = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attrString)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
                .lineSpacing(4)
                .textSelection(.enabled)
        } else {
            Text(content)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }
}
