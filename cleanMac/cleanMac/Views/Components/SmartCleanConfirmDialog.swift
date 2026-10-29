import SwiftUI
import AppKit

/// 智能清理确认：完整展示清理清单，确认前允许逐项调整。
struct SmartCleanConfirmDialog: View {
    let plan: SmartCleanPlan
    @Binding var selectedPaths: Set<String>
    let onAddToWhitelist: (FileItem) -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var selectedItems: [FileItem] {
        plan.items.filter { selectedPaths.contains($0.path) }
    }

    private var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    private var allSelected: Binding<Bool> {
        Binding(
            get: { !plan.items.isEmpty && plan.items.allSatisfy { selectedPaths.contains($0.path) } },
            set: { selectedPaths = $0 ? Set(plan.items.map(\.path)) : [] }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(24)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    summaryTile("推荐项目", value: "\(plan.items.count) 项", tint: .blue)
                    summaryTile("已选项目", value: "\(selectedItems.count) 项", tint: .orange)
                    summaryTile("逻辑大小", value: FileSizeFormatter.string(fromByteCount: selectedSize), tint: .green)
                }

                if !plan.categorySummary.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(plan.categorySummary.indices, id: \.self) { index in
                                let entry = plan.categorySummary[index]
                                Text("\(entry.category.rawValue) · \(entry.count)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(entry.category.color)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(entry.category.color.opacity(0.11), in: Capsule())
                            }
                        }
                    }
                }

                HStack {
                    Toggle("全选推荐项", isOn: allSelected)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("已选 \(selectedItems.count) / \(plan.items.count)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            ScrollView {
                if plan.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 26))
                            .foregroundColor(.green)
                        Text("没有待清理项目")
                            .font(.system(size: 14, weight: .semibold))
                        Text("推荐项已加入白名单或不再需要清理。")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(plan.items) { item in
                            row(item)
                        }
                    }
                    .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surfaceSunk.opacity(0.55))

            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
        }
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .elevatedShadow()
        .onExitCommand(perform: onCancel)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 21, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 5) {
                Text("智能清理确认")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text("所选缓存和日志将移到废纸篓，可在设置中恢复。清空废纸篓需单独确认。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .help("关闭")
            .accessibilityLabel("关闭智能清理确认")
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("将移到废纸篓 \(selectedItems.count) 项 · 逻辑大小 \(FileSizeFormatter.string(fromByteCount: selectedSize))；清空后才可能释放空间。")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("取消")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Label("清理所选项目", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(CapsuleGradientButtonStyle())
                .opacity(selectedItems.isEmpty ? 0.5 : 1)
                .disabled(selectedItems.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func summaryTile(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ item: FileItem) -> some View {
        let isSelected = selectedPaths.contains(item.path)
        return Button {
            if isSelected {
                selectedPaths.remove(item.path)
            } else {
                selectedPaths.insert(item.path)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17))
                    .foregroundColor(isSelected ? .blue : .secondary)

                FileItemIcon(file: item, size: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(item.path)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.path)
                }

                Spacer(minLength: 8)
                Text(item.sizeFormatted)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.blue.opacity(0.07) : Theme.surfaceRaised,
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name)，\(isSelected ? "已选中" : "未选中")")
        .accessibilityHint("点击切换是否清理")
        .contextMenu {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            } label: {
                Label("在 Finder 中显示", systemImage: "folder")
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.path, forType: .string)
            } label: {
                Label("复制路径", systemImage: "doc.on.doc")
            }
            Divider()
            Button {
                onAddToWhitelist(item)
            } label: {
                Label("加入白名单", systemImage: "shield.lefthalf.filled")
            }
        }
    }
}

private struct CapsuleGradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(Capsule(style: .continuous).fill(Theme.accentGradient))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.springSnappy, value: configuration.isPressed)
    }
}
