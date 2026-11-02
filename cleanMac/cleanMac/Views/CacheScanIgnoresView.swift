import SwiftUI
import Combine

struct CacheScanIgnoresView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [CacheScanIgnoreStore.Record] = []
    @State private var searchText = ""

    private var filteredRecords: [CacheScanIgnoreStore.Record] {
        guard !searchText.isEmpty else { return records }
        return records.filter { $0.path.localizedCaseInsensitiveContains(searchText)
            || $0.applicationName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("自动忽略的扫描路径").font(.system(size: 20, weight: .bold))
                }
                Spacer()
                Menu {
                    Text("完整扫描未发现缓存的目录会暂时跳过。")
                    Text("记录最长有效 24 小时，目录变化时提前复查。")
                    Text("恢复后，下次扫描会重新检查。")
                } label: { Image(systemName: "info.circle") }
                    .menuStyle(.borderlessButton).fixedSize().help("自动忽略说明")
                    .accessibilityLabel("自动忽略说明")
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                TextField("搜索软件名称或路径", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("搜索自动忽略的路径")
                Text("\(records.count) 条记录").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize()
                Button("恢复全部") { CacheScanIgnoreStore.shared.removeAll() }
                    .disabled(records.isEmpty)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredRecords) { record in
                        HStack(spacing: 12) {
                            Image(systemName: "folder.badge.minus").font(.system(size: 24))
                                .foregroundStyle(Color.accentColor).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(record.applicationName).font(.system(size: 13, weight: .semibold))
                                Text(record.path).font(.system(size: 11)).foregroundStyle(.secondary)
                                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(record.path)
                                HStack(spacing: 4) {
                                    Text("扫描于")
                                    Text(record.scannedAt, style: .date)
                                    Text(record.scannedAt, style: .time)
                                }
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button("恢复扫描") { CacheScanIgnoreStore.shared.remove(record.path) }
                                .help("下次扫描重新检查此目录")
                                .accessibilityLabel("恢复扫描 \(record.applicationName)：\(record.path)")
                        }
                        .padding(12)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .contextMenu {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.path)])
                            } label: {
                                Label("在 Finder 中显示", systemImage: "folder")
                            }
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(record.path, forType: .string)
                            } label: {
                                Label("复制路径", systemImage: "doc.on.doc")
                            }
                            Divider()
                            Button {
                                CacheScanIgnoreStore.shared.remove(record.path)
                            } label: {
                                Label("恢复扫描", systemImage: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .overlay {
                if filteredRecords.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: records.isEmpty ? "checkmark.circle" : "magnifyingglass").font(.system(size: 32))
                        Text(records.isEmpty ? "暂无自动忽略的路径" : "没有匹配的路径")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 700, height: 520)
        .background(Theme.canvas)
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: CacheScanIgnoreStore.didChange).receive(on: RunLoop.main)) { _ in reload() }
    }

    private func reload() { records = CacheScanIgnoreStore.shared.allRecords }
}
