import SwiftUI

/// 搜索按钮在原位展开，保持单行高度；不占满工具栏的剩余空间。
struct ExpandableSearchField: View {
    let placeholder: String
    @Binding var text: String
    @State private var expanded = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isExpanded: Bool { expanded || !text.isEmpty }
    private var motion: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    var body: some View {
        HStack(spacing: isExpanded ? 8 : 0) {
            Button {
                if isExpanded { focused = true }
                else { withAnimation(motion) { expanded = true } }
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(isExpanded ? .secondary : Theme.actionInk)
                    .frame(width: isExpanded ? 16 : 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(placeholder).accessibilityLabel(placeholder)
            if isExpanded {
                TextField(placeholder, text: $text).textFieldStyle(.plain).focused($focused)
                    .accessibilityLabel(placeholder)
                    .task {
                        // 等输入框挂载并完成展开，再交付键盘焦点。
                        do { try await Task.sleep(for: .milliseconds(240)) } catch { return }
                        focused = true
                    }
                    .transition(.opacity)
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.actionInk)
                        .frame(width: 20, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("关闭搜索并清除条件")
                .accessibilityLabel("关闭搜索并清除条件")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, isExpanded ? 10 : 0)
        .frame(minWidth: isExpanded ? 160 : 36,
               idealWidth: isExpanded ? 220 : 36,
               maxWidth: isExpanded ? 260 : 36)
        .frame(height: 36)
        .font(.system(size: 13))
        .background(Theme.controlWash)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.controlBorder))
        .animation(motion, value: isExpanded)
        .onExitCommand(perform: close)
    }

    private func close() {
        focused = false
        withAnimation(motion) {
            text = ""
            expanded = false
        }
    }
}
