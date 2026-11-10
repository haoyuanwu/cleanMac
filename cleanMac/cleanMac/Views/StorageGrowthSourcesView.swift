import SwiftUI

/// 缓存增长有可比的目录级基线；不将其表述为整盘增长的完整解释。
struct StorageGrowthSourcesView: View {
    @State private var expanded = Set<String>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: MainViewModel
    private var comparison: CacheScanComparison? { viewModel.applicationCacheComparison }
    private var refreshing: Bool { viewModel.scanResults[.applicationCache]?.isScanning == true }

    var body: some View {
        StorageTimelinePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("空间增长来源", systemImage: "chart.line.uptrend.xyaxis").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button(refreshing ? "更新中…" : "更新缓存扫描") {
                        Task { await viewModel.scanCategory(.applicationCache) }
                    }.disabled(refreshing).buttonStyle(ReadableControlButtonStyle())
                }
                Text("当前追踪应用缓存的增长；系统快照、应用本体和其他文件的变化不在此范围内。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if refreshing { ProgressView("正在更新增长来源…").controlSize(.small) }
                if let comparison {
                    Text(comparison.description).font(.system(size: 12)).foregroundStyle(.secondary)
                    if comparison.complete, let previous = comparison.previousDate {
                        Text(previous.formatted() + " → " + comparison.date.formatted()).font(.caption).foregroundStyle(.secondary)
                        if comparison.growth.isEmpty { Text("两次可比扫描间未发现缓存增长。").font(.system(size: 13)) }
                        ForEach(comparison.growth.filter { $0.bytes > 0 }, id: \.application) { growth in
                            DisclosureGroup(isExpanded: Binding(get: { expanded.contains(growth.application) }, set: { value in
                                withAnimation(reduceMotion ? nil : Theme.ease) {
                                    if value { expanded.insert(growth.application) } else { expanded.remove(growth.application) }
                                }
                            })) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(growth.paths, id: \.self) { path in
                                        HStack(spacing: 12) {
                                            Text(path).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                                            Spacer()
                                            Button("查看") { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") }
                                                .buttonStyle(ReadableControlButtonStyle(tint: .blue))
                                                .accessibilityLabel("在 Finder 中查看 " + path)
                                        }.font(.system(size: 12))
                                    }
                                }.padding(.top, 8)
                            } label: {
                                HStack {
                                    Text(growth.application).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text("+" + FileSizeFormatter.string(fromByteCount: growth.bytes)).monospacedDigit().foregroundStyle(.orange)
                                }.font(.system(size: 13))
                            }
                        }
                    } else {
                        Text("需要两次相同规则下的完整扫描，才能比较增长来源。").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                } else {
                    Text("尚无缓存对比记录。完成首次扫描建立基线，再次扫描后即可查看增长的软件和路径。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }
}
