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
                    if !viewModel.chatHistory.isEmpty && viewModel.errorMessage == nil {
                        Button(action: {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            let text = viewModel.chatHistory.map { "\($0.role.rawValue.capitalized): \($0.content)" }.joined(separator: "\n\n")
                            pb.setString(text, forType: .string)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { showCopiedToast = true }
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                withAnimation(.easeOut(duration: 0.2)) { showCopiedToast = false }
                            }
                        }) {
                            Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(showCopiedToast ? .green : .white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                        .help("Copy chat history")
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let error = viewModel.errorMessage {
                            VStack(spacing: 12) {
                                Spacer().frame(height: 60)
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.red)
                                    .id("bottom")
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
                            if viewModel.chatHistory.isEmpty && !viewModel.isLoading {
                                VStack(spacing: 12) {
                                    Image(systemName: "sparkles.rectangle.stack")
                                        .font(.system(size: 40))
                                        .foregroundColor(.purple.opacity(0.8))
                                    Text("Ask me anything about this capture!")
                                        .font(.headline)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 60)
                                .id("bottom")
                            } else {
                                ForEach(Array(viewModel.chatHistory.enumerated()), id: \.offset) { i, msg in
                                    if msg.role == .user {
                                        HStack {
                                            Spacer()
                                            Text(msg.content)
                                                .padding(12)
                                                .background(Color.blue.opacity(0.8))
                                                .foregroundColor(.white)
                                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                        }
                                        .padding(.horizontal, 16)
                                    } else if msg.role == .system {
                                        Text(msg.content)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.5))
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    } else {
                                        NativeMarkdownView(text: msg.content)
                                            .padding(.horizontal, 16)
                                    }
                                }
                                
                                if viewModel.isLoading {
                                    if viewModel.currentStreamText.isEmpty {
                                        AgentThinkingView()
                                            .padding(.horizontal, 16)
                                            .id("bottom")
                                    } else {
                                        NativeMarkdownView(text: viewModel.currentStreamText)
                                            .padding(.horizontal, 16)
                                            .id("bottom")
                                    }
                                } else {
                                    Spacer().frame(height: 1).id("bottom")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
                .onChange(of: viewModel.chatHistory.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: viewModel.currentStreamText) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            
            // Input Area
            Divider().background(Color.white.opacity(0.1))
            
            if !viewModel.promptQueue.isEmpty {
                HStack {
                    Text("\(viewModel.promptQueue.count) prompt(s) in queue...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, -4)
            }
            
            HStack {
                TextField("Ask AI about this capture...", text: $viewModel.inputText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(8)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(8)
                    .onSubmit {
                        if !viewModel.inputText.isEmpty {
                            viewModel.sendMessage(viewModel.inputText)
                        }
                    }
                
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        Button(action: {
                            viewModel.stopGenerating()
                        }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .help("Stop Generating")
                    }
                    
                    Button(action: {
                        if !viewModel.inputText.isEmpty {
                            viewModel.sendMessage(viewModel.inputText)
                        }
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(viewModel.inputText.isEmpty ? .white.opacity(0.2) : .blue)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.isLoading ? "Queue Prompt" : "Send Prompt")
                }
            }
            .padding(12)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHoveringContent = hovering
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}

@MainActor
public class AIResultViewModel: ObservableObject {
    @Published public var isLoading: Bool = false
    @Published public var chatHistory: [AIChatMessage] = []
    @Published public var currentStreamText: String = ""
    @Published public var errorMessage: String? = nil
    @Published public var inputText: String = ""
    @Published public var promptQueue: [String] = []
    
    private var currentTask: Task<Void, Never>? = nil
    
    public var cgImage: CGImage?
    
    public init() {
        if UserDefaults.standard.string(forKey: "ai_output_language") == nil {
            let sysLang = Locale.current.language.languageCode?.identifier ?? "en"
            let supported = ["en", "vi", "ja"]
            UserDefaults.standard.set(supported.contains(sysLang) ? sysLang : "en", forKey: "ai_output_language")
        }
        
        let lang = UserDefaults.standard.string(forKey: "ai_output_language") ?? "en"
        let msg: String
        switch lang {
        case "vi": msg = "Chào bạn! Tôi có thể giúp gì cho bạn với hình ảnh này?"
        case "ja": msg = "こんにちは！この画像について何でも聞いてください。"
        default: msg = "Hello! I am ready to answer any questions about this capture."
        }
        
        self.chatHistory = [AIChatMessage(role: .assistant, content: msg)]
    }
    public func stopGenerating() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
        if !currentStreamText.isEmpty {
            chatHistory.append(AIChatMessage(role: .assistant, content: currentStreamText))
            currentStreamText = ""
        }
        processNextInQueue()
    }
    
    private func processNextInQueue() {
        if !promptQueue.isEmpty {
            let next = promptQueue.removeFirst()
            startGeneration(for: next)
        }
    }

    public func sendMessage(_ text: String) {
        let msg = AIChatMessage(role: .user, content: text)
        chatHistory.append(msg)
        inputText = ""
        errorMessage = nil
        
        if isLoading {
            promptQueue.append(text)
            return
        }
        
        startGeneration(for: text)
    }
    
    private func startGeneration(for text: String) {
        isLoading = true
        currentStreamText = ""
        
        currentTask = Task { [weak self] in
            guard let self = self else { return }
            if let ai = Phase3Workflow() {
                do {
                    // Truncate history if > 10
                    var contextHistory = self.chatHistory
                    if contextHistory.count > 10 {
                        let summaryPrompt = "Summarize the key context of this conversation briefly in one paragraph: \n" + contextHistory.map { "\($0.role.rawValue.capitalized): \($0.content)" }.joined(separator: "\n")
                        let summary = try await ai.provider.generateText(prompt: summaryPrompt, image: nil)
                        
                        await MainActor.run {
                            self.chatHistory = [
                                AIChatMessage(role: .system, content: "Context from previous conversation: " + summary),
                                AIChatMessage(role: .user, content: text)
                            ]
                        }
                        contextHistory = self.chatHistory
                    }
                    let lang = UserDefaults.standard.string(forKey: "ai_output_language") ?? "en"
                    let langName = lang == "vi" ? "Vietnamese" : (lang == "ja" ? "Japanese" : "English")
                    let systemPromptStr = """
                    You are an intelligent AI assistant built directly into BerryShot, created by notex.work.
                    Your primary job is to support the user in utilizing capture features, analyzing images, extracting text, explaining code, and addressing any image-capture-related inquiries.
                    
                    **App Capabilities**: BerryShot currently supports taking screenshots, screen recording (with mic/audio), scrolling capture, image annotations (arrows, shapes, text, drawing), text extraction (OCR), pinning images to screen, and AI image analysis.
                    
                    **Handling Feature Requests**: If the user asks how to do something (e.g., "I want to record the screen"), you MUST prioritize explaining how to do it using BerryShot's existing features. If they ask for a feature that BerryShot does NOT have, clearly inform them that it is not supported in the current app, and politely ask to confirm if they are referring to another system or application.
                    
                    If the user asks who you are, introduce yourself as the AI assistant created by notex.work, capable of assisting with capture workflows and image analysis.
                    You must answer in the language the user asks you in, unless specifically requested otherwise. Use \(langName) as your default preferred language if uncertain.
                    Format your response clearly using Markdown (bold, lists, code blocks).
                    Always address the user's question directly, accurately, and concisely.
                    """
                    let systemPrompt = AIChatMessage(role: .system, content: systemPromptStr)
                    let apiMessages = [systemPrompt] + contextHistory
                    let stream = ai.provider.generateChatStream(messages: apiMessages, image: self.cgImage)
                    for try await chunk in stream {
                        if Task.isCancelled { break }
                        await MainActor.run {
                            self.currentStreamText += chunk
                        }
                    }
                    
                    await MainActor.run {
                        if !Task.isCancelled {
                            self.chatHistory.append(AIChatMessage(role: .assistant, content: self.currentStreamText))
                            self.currentStreamText = ""
                            self.isLoading = false
                            self.processNextInQueue()
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.errorMessage = "Failed: \(error.localizedDescription)"
                            self.isLoading = false
                            self.processNextInQueue()
                        }
                    }
                }
            } else {
                await MainActor.run {
                    self.errorMessage = "AI Configuration Missing."
                    self.isLoading = false
                    self.processNextInQueue()
                }
            }
        }
    }
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
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
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

struct AgentThinkingView: View {
    @State private var stepIndex = 0
    private let steps = [
        "Analyzing visual context...",
        "Extracting relevant data...",
        "Formulating intelligence...",
        "Refining response..."
    ]
    
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            
            Text(steps[stepIndex])
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.purple.opacity(0.8))
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        stepIndex = (stepIndex + 1) % steps.count
                    }
                }
            }
        }
    }
}
