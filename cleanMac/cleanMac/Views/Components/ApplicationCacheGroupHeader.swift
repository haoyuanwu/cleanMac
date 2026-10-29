import SwiftUI

/// 展开与选择分开操作；组内选择只作用于当前筛选出的缓存项。
struct ApplicationCacheGroupHeader: View {
    let application: CacheApplication?
    let files: [FileItem]
    @Binding var selectedFiles: Set<FileItem.ID>
    @Binding var isExpanded: Bool
    @State private var appIcon: NSImage?

    private var name: String { application?.name ?? "其他应用缓存" }
    private var selectedCount: Int { files.filter { selectedFiles.contains($0.id) }.count }
    private var allSelected: Bool { !files.isEmpty && selectedCount == files.count }
    private var selectionSymbol: String {
        allSelected ? "checkmark.square.fill" : (selectedCount > 0 ? "minus.square.fill" : "square")
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: Binding(
                get: { allSelected },
                set: { selected in
                    let ids = Set(files.map(\.id))
                    if selected { selectedFiles.formUnion(ids) }
                    else { selectedFiles.subtract(ids) }
                }
            )) {
                Image(systemName: selectionSymbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selectedCount > 0 ? Color.accentColor : .secondary)
                    .frame(width: 28, height: 36)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("选择 \(name) 的缓存")
            .accessibilityValue("已选 \(selectedCount) 项，共 \(files.count) 项")
            .help(allSelected ? "取消选择该软件的缓存" : "选择该软件的全部缓存")

            DisclosureGroup(isExpanded: $isExpanded) {
                // 子项由外层 LazyVStack 按需创建，避免在组内嵌套滚动列表。
            } label: {
                HStack(spacing: 12) {
                    Group {
                        if let appIcon {
                            Image(nsImage: appIcon).resizable().scaledToFit()
                        } else {
                            Image(systemName: "app")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .help(name)
                        Text("\(files.count) 项缓存 · \(isExpanded ? "收起列表" : "展开查看")")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(FileSizeFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.size }))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
            .disclosureGroupStyle(ApplicationCacheDisclosureStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .gradientGlass(cornerRadius: 14)
        .task(id: application) { appIcon = application?.icon }
    }
}

private struct ApplicationCacheDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : Theme.ease) {
                configuration.isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                configuration.label
                Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 28)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isExpanded ? "已展开" : "已收起")
        .accessibilityHint("显示或隐藏缓存文件列表")
    }
}
