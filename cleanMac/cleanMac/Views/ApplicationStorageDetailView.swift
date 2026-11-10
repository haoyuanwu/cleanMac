import SwiftUI

struct ApplicationStorageDetailView: View {
    let application: FileItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var monitor = HighResourceMonitor.shared
    @State private var estimate: AppLeftoverEstimate?
    @State private var loading = true

    private var usage: ApplicationResourceUsage? {
        monitor.allApplications.first { $0.application.path == application.path }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                if let icon = application.appIcon { Image(nsImage: icon).resizable().frame(width: 40, height: 40) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(application.name).font(.system(size: 22, weight: .bold))
                    Text("应用占用详情").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 18) {
                CompactListMetric(title: "应用本体", value: estimate?.appSizeFormatted ?? application.sizeFormatted)
                if let estimate { CompactListMetric(title: "关联数据（已统计）", value: estimate.leftoverSizeFormatted) }
            }.padding(14).gradientGlass(cornerRadius: 14)
            Text("以下是识别到的关联路径，不代表全部占用。缓存和日志可能重建；应用数据、设置与共享容器可能包含需要保留的内容。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if loading { ProgressView("正在识别关联数据…") }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let estimate {
                        ForEach(estimate.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                        if estimate.leftovers.isEmpty { Text("未识别到关联数据。受保护或无法读取的位置可能未被统计。").foregroundStyle(.secondary) }
                        ForEach(estimate.leftovers) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.categoryLabel).fontWeight(.semibold)
                                    if item.isShared { Text("共享 · 谨慎处理").foregroundStyle(.orange) }
                                    Spacer()
                                    Text(item.sizeFormatted).monospacedDigit()
                                }
                                Text(item.path).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                                Text(item.impact).foregroundStyle(.secondary)
                                DisclosureGroup("识别依据") { Text(item.ownershipReason).foregroundStyle(.secondary) }
                                Button("在 Finder 中查看") { NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "") }
                            }.font(.system(size: 12)).padding(14).gradientGlass(cornerRadius: 12)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("关联进程").font(.system(size: 14, weight: .semibold))
                        if let usage {
                            Text("\(usage.processCount) 个进程 · 内存 \(FileSizeFormatter.string(fromByteCount: Int64(clamping: usage.memory)))")
                            ForEach(usage.processes) { process in
                                HStack {
                                    Text("PID \(process.pid)").monospacedDigit()
                                    Text(process.path).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(FileSizeFormatter.string(fromByteCount: Int64(clamping: process.memory)))
                                }
                            }
                        } else {
                            Text("暂无进程采样；应用可能未运行，或资源监控尚未取得数据。").foregroundStyle(.secondary)
                        }
                    }.font(.system(size: 12)).padding(14).gradientGlass(cornerRadius: 12)
                }
            }
            HStack {
                Button("在 Finder 中显示应用") { NSWorkspace.shared.selectFile(application.path, inFileViewerRootedAtPath: "") }
                Spacer()
                Text("如需清理，请返回对应清理页面核对后操作。") .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(24).frame(minWidth: 600, idealWidth: 680, minHeight: 540, idealHeight: 640)
            .task(id: application.path) {
                let result = await AppLeftoverScanner.estimate(for: application.path)
                guard !Task.isCancelled else { return }
                estimate = result
                loading = false
            }
    }
}
