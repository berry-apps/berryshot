import SwiftUI

public struct AIResultView: View {
    @ObservedObject var viewModel: AIResultViewModel
    @State private var isHoveringContent = false
    @State private var showCopiedToast = false
    
    public var body: some View {
        VStack(spacing: 0) {

            // Content Area
            ZStack(alignment: .topTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if viewModel.isLoading {
                            VStack(spacing: 16) {
                                Spacer().frame(height: 80)
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Analyzing image with AI...")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            
                        } else if let error = viewModel.errorMessage {
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
                            if let attrString = try? AttributedString(markdown: viewModel.resultText, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)) {
                                Text(attrString)
                                    .font(.system(size: 14, weight: .regular, design: .default))
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                    .padding(24)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(viewModel.resultText)
                                    .font(.system(size: 14, weight: .regular, design: .default))
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                                    .padding(24)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                
                // Floating Copy Button
                if isHoveringContent && !viewModel.resultText.isEmpty && !viewModel.isLoading && viewModel.errorMessage == nil {
                    Button(action: {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(viewModel.resultText, forType: .string)
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { showCopiedToast = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation(.easeOut(duration: 0.2)) { showCopiedToast = false }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: showCopiedToast ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                            if showCopiedToast {
                                Text("Copied")
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .foregroundColor(showCopiedToast ? .white : .primary)
                        .padding(.horizontal, showCopiedToast ? 12 : 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(showCopiedToast ? Color.green : Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .onContinuousHover { phase in
                        switch phase {
                        case .active: NSCursor.pointingHand.set()
                        case .ended: NSCursor.arrow.set()
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
        .frame(width: 480, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

public class AIResultViewModel: ObservableObject {
    @Published public var isLoading: Bool = true
    @Published public var resultText: String = ""
    @Published public var errorMessage: String? = nil
    
    public init() {}
}
