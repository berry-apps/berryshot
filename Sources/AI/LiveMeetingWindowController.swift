import Cocoa
import SwiftUI

class LiveMeetingWindowController: NSWindowController {
    convenience init(onGenerateMinutes: @escaping () -> Void) {
        let size = CGSize(width: 320, height: 480)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenFrame.maxX - size.width - 16,
            y: screenFrame.minY + 100
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        self.init(window: panel)

        let rootView = LiveMeetingView(
            service: LiveTranscriptionService.shared,
            onGenerateMinutes: onGenerateMinutes,
            onClose: { [weak self] in self?.close() }
        )
        panel.contentView = NSHostingView(rootView: rootView)
    }

    func show() {
        window?.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct LiveMeetingView: View {
    @ObservedObject var service: LiveTranscriptionService
    let onGenerateMinutes: () -> Void
    let onClose: () -> Void

    @State private var isGenerating = false
    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            transcriptContent
            Divider().opacity(0.2)
            generateButton
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 14))
            Text("Live Meeting Notes")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
                .opacity(pulseOpacity)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseOpacity)
                .onAppear { pulseOpacity = 0.3 }
            if !service.liveTranscript.isEmpty {
                Button(action: copyTranscript) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Copy transcript")
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func copyTranscript() {
        let text = service.fullTranscriptText
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var hasActivity: Bool {
        !service.liveTranscript.isEmpty || !service.partialMicText.isEmpty || !service.partialSystemText.isEmpty
    }

    private var isConnected: Bool {
        service.statusMessage.contains("✓") || service.statusMessage.contains("connecting")
    }

    @ViewBuilder
    private var transcriptContent: some View {
        if !hasActivity {
            VStack(spacing: 8) {
                Image(systemName: isConnected ? "waveform.circle.fill" : "waveform")
                    .font(.system(size: 28))
                    .foregroundColor(isConnected ? .green : .white.opacity(0.3))
                    .symbolEffect(.pulse, isActive: isConnected)
                Text(isConnected ? "Listening..." : "Waiting for audio...")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                if !service.statusMessage.isEmpty {
                    Text(service.statusMessage)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(isConnected ? .green.opacity(0.8) : .yellow.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(service.liveTranscript) { seg in
                            TranscriptRowView(segment: seg).id(seg.id)
                        }
                        // Live partial text — mic
                        if !service.partialMicText.isEmpty {
                            PartialTextRow(text: service.partialMicText, source: .mic)
                                .id("partial-mic")
                        }
                        // Live partial text — system audio
                        if !service.partialSystemText.isEmpty {
                            PartialTextRow(text: service.partialSystemText, source: .systemAudio)
                                .id("partial-sys")
                        }
                    }
                    .padding(12)
                }
                .onChange(of: service.liveTranscript.count) {
                    if let last = service.liveTranscript.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: service.partialMicText) {
                    if !service.partialMicText.isEmpty {
                        withAnimation { proxy.scrollTo("partial-mic", anchor: .bottom) }
                    }
                }
                .onChange(of: service.partialSystemText) {
                    if !service.partialSystemText.isEmpty {
                        withAnimation { proxy.scrollTo("partial-sys", anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var generateButton: some View {
        Button(action: {
            isGenerating = true
            onGenerateMinutes()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isGenerating = false }
        }) {
            HStack(spacing: 6) {
                if isGenerating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "doc.text.fill").font(.system(size: 11))
                }
                Text("Generate Meeting Minutes")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(service.liveTranscript.isEmpty ? .white.opacity(0.4) : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(service.liveTranscript.isEmpty ? Color.white.opacity(0.05) : Color.blue.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(service.liveTranscript.isEmpty || isGenerating)
        .padding(12)
    }
}

struct PartialTextRow: View {
    let text: String
    let source: TranscriptSegment.Source

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: source == .mic ? "mic.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10))
                .foregroundColor((source == .mic ? Color.blue : Color.orange).opacity(0.5))
                .frame(width: 14)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
                .italic()
        }
    }
}

struct TranscriptRowView: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: segment.source == .mic ? "mic.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10))
                .foregroundColor(segment.source == .mic ? .blue : .orange)
                .frame(width: 14)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(segment.source == .mic ? "You" : "Other")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(segment.source == .mic ? .blue : .orange)
                    Text(formatTime(segment.timestamp))
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                }
                Text(segment.text)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
