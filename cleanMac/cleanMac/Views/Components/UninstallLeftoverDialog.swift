import SwiftUI

/// 确认卸载时显示归属依据；共享和用户数据保留为显式选择。
struct UninstallLeftoverDialog: View {
    let estimates: [AppLeftoverEstimate]
    let appCount: Int
    let isLoading: Bool
    let runningApplications: [RunningUninstallApplication]
    let isQuitting: Bool
    let statusMessage: String?
    @Binding var selectedLeftoverPaths: Set<String>
    let onQuit: () -> Void
    let onRefresh: () -> Void
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var allLeftovers: [AppLeftoverItem] { AppLeftoverSelection.merged(estimates) }
    private var selected: [AppLeftoverItem] {
        AppLeftoverSelection.coveredOnce(allLeftovers.filter { $0.isSelectable && selectedLeftoverPaths.contains($0.path) })
    }
    private var exclusive: [AppLeftoverItem] { allLeftovers.filter { $0.isSelectable && !$0.isShared } }
    private var issues: [String] { estimates.flatMap(\.issues) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("核对卸载清单 · \(appCount) 个应用").font(.system(size: 21, weight: .bold))
                    Text("应用和所选数据将移到废纸篓。默认只选明确归属的缓存、日志和状态存档。")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 12) {
                metric("应用逻辑大小", bytes: estimates.reduce(0) { $0 + $1.appSize })
                metric("已选关联数据", bytes: selected.reduce(0) { $0 + $1.size })
                Text("\(selected.count) 项已选").font(.system(size: 13, weight: .medium)).monospacedDigit()
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    runtimeNotice
                    if let statusMessage {
                        Text(statusMessage).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
                    }
                    if isLoading {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text("正在关联应用数据、容器与启动项…").font(.system(size: 13))
                        }.padding(.vertical, 28).frame(maxWidth: .infinity)
                    }
                    ForEach(estimates, id: \.appPath) { estimate in
                        HStack(spacing: 12) {
                            Image(systemName: "app").font(.system(size: 22)).foregroundStyle(.indigo).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(estimate.displayName).font(.system(size: 14, weight: .semibold))
                                Text(estimate.appPath).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(estimate.appSizeFormatted).font(.system(size: 13)).monospacedDigit()
                        }.padding(12).background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if !issues.isEmpty {
                        DisclosureGroup("\(issues.count) 条读取提示 · 关联清单可能不完整") {
                            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                                Text(issue).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }.font(.system(size: 12)).foregroundStyle(.orange)
                    }
                    if !isLoading, allLeftovers.isEmpty {
                        Text(issues.isEmpty ? "未发现已确认的关联数据。" : "未找到可列出的项目；部分路径未能读取，请展开提示查看。")
                            .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 20)
                    }
                    if !allLeftovers.isEmpty {
                        Toggle("全选非共享项目", isOn: Binding(
                            get: { !exclusive.isEmpty && exclusive.allSatisfy { selectedLeftoverPaths.contains($0.path) } },
                            set: { on in
                                if on { selectedLeftoverPaths.formUnion(exclusive.map(\.path)) }
                                else { selectedLeftoverPaths.subtract(exclusive.map(\.path)) }
                            }
                        )).toggleStyle(.checkbox).font(.system(size: 12)).disabled(exclusive.isEmpty || isQuitting)
                        ForEach(allLeftovers) { item in leftoverRow(item) }
                    }
                }.padding(.vertical, 4)
            }
            Divider()
            if selected.contains(where: \.isShared) {
                Label("已选择共享容器，可能影响同组其他应用的数据。", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            HStack(spacing: 16) {
                Text("启动项与仅名称匹配的目录只供核对；恢复入口位于设置的清理记录中。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: onConfirm) {
                    Text(isLoading ? "正在检查…" : selected.isEmpty ? "仅卸载应用" : "卸载并回收 \(selected.count) 项")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 18).frame(minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || isQuitting || !runningApplications.isEmpty)
            }
        }
        .padding(22).background(Theme.canvas, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.08)))
        .elevatedShadow()
    }

    private var runtimeNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(runningApplications.isEmpty ? "未检测到相关应用正在运行" : "先保存工作并退出相关应用", systemImage: runningApplications.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.system(size: 13, weight: .medium))
            if !runningApplications.isEmpty {
                Text(runningApplications.map(\.name).joined(separator: "、")).font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button(action: onQuit) {
                        HStack(spacing: 6) {
                            if isQuitting { ProgressView().controlSize(.small) }
                            Text(isQuitting ? "等待正常退出…" : "请求正常退出")
                        }
                    }.disabled(isQuitting)
                    Button("重新检查", action: onRefresh).disabled(isQuitting)
                }
                Text("不强制结束进程；如出现保存提示或应用拒绝退出，请手动处理后重新检查。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background((runningApplications.isEmpty ? Color.green : .orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func leftoverRow(_ item: AppLeftoverItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if item.isSelectable {
                    Toggle("选择 \(item.name)", isOn: Binding(
                        get: { selectedLeftoverPaths.contains(item.path) },
                        set: { on in
                            if on { selectedLeftoverPaths.insert(item.path) } else { selectedLeftoverPaths.remove(item.path) }
                        }
                    )).labelsHidden().toggleStyle(.checkbox).disabled(isQuitting)
                } else { Image(systemName: "lock").foregroundStyle(.secondary).accessibilityLabel("仅供核对") }
                Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if item.isShared { Text("可能共享").font(.system(size: 12)).foregroundStyle(.orange) }
                Text(item.categoryLabel).font(.system(size: 12)).foregroundStyle(.secondary)
                Text(item.sizeFormatted).font(.system(size: 13)).monospacedDigit()
            }
            Text(item.path).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            DisclosureGroup("归属依据与清理影响") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.ownershipReason)
                    Text(item.impact).foregroundStyle(.secondary)
                    if !item.isSelectable { Text("此项仅展示，不随卸载回收。").foregroundStyle(.secondary) }
                }.font(.system(size: 12)).textSelection(.enabled).padding(.top, 6)
            }.font(.system(size: 12))
        }.padding(12).background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            .contextMenu {
                Button("在 Finder 中显示") { NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "") }
                Button("复制路径") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.path, forType: .string)
                }
            }
    }

    private func metric(_ title: String, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(FileSizeFormatter.string(fromByteCount: bytes)).font(.system(size: 16, weight: .semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
