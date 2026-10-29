import SwiftUI
import Combine

struct CleaningHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [CleaningRecord] = []
    @State private var search = ""
    @State private var restorableOnly = false
    @State private var restoring: UUID?
    @State private var feedback: String?
    @State private var storeError: String?

    private var filtered: [CleaningRecord] {
        records.filter {
            (!restorableOnly || $0.state == .movedToTrash)
                && (search.isEmpty || $0.originalPath.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("清理记录与恢复").font(.system(size: 22, weight: .bold))
                    Text("常规清理移到废纸篓；永久删除的项目无法恢复。")
                        .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 16) {
                TextField("搜索应用、文件名或原路径", text: $search).textFieldStyle(.roundedBorder)
                Toggle("仅看移到废纸篓的项目", isOn: $restorableOnly).toggleStyle(.checkbox)
            }
            if let storeError { Label(storeError, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange) }
            Divider()
            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text(records.isEmpty ? "还没有清理记录" : "没有符合条件的记录").font(.system(size: 15, weight: .medium))
                    Text("从此版本开始记录操作；此前的清理不会补写历史。")
                        .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(filtered) { record in row(record) }
                    }
                }
            }
            Divider()
            Text("恢复不覆盖同名项目。原目录缺失、权限不足或废纸篓项目变化时，请在 Finder 中核对。恢复后重新扫描可更新清理清单。")
                .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
        }
        .padding(24).frame(width: 820, height: 600).background(Theme.canvas)
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: CleaningHistoryStore.didChange).receive(on: RunLoop.main)) { _ in refresh() }
        .alert("恢复结果", isPresented: Binding(get: { feedback != nil }, set: { if !$0 { feedback = nil } })) {
            Button("好") { feedback = nil }
        } message: { Text(feedback ?? "") }
    }

    private func row(_ record: CleaningRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: record.state == .restored ? "checkmark.circle" : "doc.text")
                    .font(.system(size: 20)).foregroundStyle(record.state == .failed ? Color.orange : Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text((record.originalPath as NSString).lastPathComponent).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text("\(record.category) · \(record.date.formatted(date: .abbreviated, time: .shortened)) · 逻辑大小 \(FileSizeFormatter.string(fromByteCount: record.logicalBytes))")
                        .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                }
                Spacer()
                Text(status(record.state)).font(.system(size: 12, weight: .medium))
                if record.state == .movedToTrash, record.trashPath != nil, record.fingerprint != nil {
                    Button {
                        restoring = record.id
                        Task {
                            do {
                                try await Task.detached(priority: .userInitiated) { try CleaningHistoryStore.shared.restore(record.id) }.value
                                feedback = "已恢复到原位置：\(record.originalPath)"
                            } catch { feedback = error.localizedDescription }
                            restoring = nil
                            refresh()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if restoring == record.id { ProgressView().controlSize(.small) }
                            Text(restoring == record.id ? "恢复中…" : "恢复")
                        }
                    }
                    .disabled(restoring != nil)
                    .accessibilityLabel("恢复 \((record.originalPath as NSString).lastPathComponent)")
                }
            }
            Text(record.originalPath).font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                .textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            if let message = record.message { Text(message).font(.system(size: 12)).foregroundStyle(.orange) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            if let trashPath = record.trashPath {
                Button("在 Finder 中查看废纸篓项目") { NSWorkspace.shared.selectFile(trashPath, inFileViewerRootedAtPath: "") }
            }
            Button("复制原路径") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.originalPath, forType: .string)
            }
        }
    }

    private func status(_ state: CleaningRecord.State) -> String {
        switch state {
        case .movedToTrash: return "已移到废纸篓"
        case .permanentlyDeleted: return "永久删除 · 不可恢复"
        case .failed: return "未完成"
        case .restored: return "已恢复"
        case .alreadyMissing: return "操作前已不存在"
        }
    }

    private func refresh() {
        records = CleaningHistoryStore.shared.records
        storeError = CleaningHistoryStore.shared.persistenceError
    }
}
