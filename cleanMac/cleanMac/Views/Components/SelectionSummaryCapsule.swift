import SwiftUI

/// 列表共用的悬浮选择汇总；按可用宽度缩短标签、收起操作文字或分行。
struct SelectionSummaryCapsule: View {
    let count: Int
    let totalSize: Int64
    let actionTitle: String
    var isBusy = false
    var onClear: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            capsule(compact: false, iconOnly: false)
            capsule(compact: true, iconOnly: false)
            capsule(compact: true, iconOnly: true)
            stackedCapsule
        }
        .background {
            Capsule()
                .fill(.regularMaterial)
                .overlay {
                    Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.16), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
    }

    private func capsule(compact: Bool, iconOnly: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            summary(compact: compact)
                .padding(.leading, compact ? 12 : 14)
                .padding(.trailing, compact ? 0 : 4)

            Divider().frame(height: 18)

            clearButton
            deleteButton(iconOnly: iconOnly)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: 52)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var stackedCapsule: some View {
        VStack(spacing: 8) {
            summary(compact: true)
            HStack(spacing: 8) {
                clearButton
                deleteButton(iconOnly: false)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func summary(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            Text("\(count)")
                .font(.system(size: compact ? 15 : 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accentGradient)
                .monospacedDigit()
            Text(compact ? "项" : "已选")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text(FileSizeFormatter.string(fromByteCount: totalSize))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("已选择 \(count) 项，共 \(FileSizeFormatter.string(fromByteCount: totalSize))")
    }

    @ViewBuilder
    private var clearButton: some View {
        if let onClear {
            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("取消选择")
            .accessibilityLabel("取消选择")
            .disabled(isBusy)
        }
    }

    private func deleteButton(iconOnly: Bool) -> some View {
        Button(role: .destructive, action: onDelete) {
            HStack(spacing: 6) {
                Image(systemName: isBusy ? "hourglass" : "trash")
                    .font(.system(size: 12, weight: .semibold))
                if !iconOnly {
                    Text(isBusy ? "处理中…" : actionTitle)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .foregroundColor(.white)
            .background {
                Capsule().fill(
                    LinearGradient(
                        colors: [Color.red.opacity(0.95), Color.red.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .shadow(color: Color.red.opacity(0.3), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .opacity(isBusy ? 0.6 : 1)
        .help(isBusy ? "正在处理所选项目" : actionTitle)
        .accessibilityLabel(isBusy ? "正在处理所选项目" : actionTitle)
    }

}
