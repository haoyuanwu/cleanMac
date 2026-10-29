import SwiftUI
import Combine

@MainActor
final class SpaceInsightsSession: ObservableObject {
    @Published var insights: [SpaceInsight] = []
    @Published var generating = false
    @Published var generatedAt: Date?
    var work: Task<Void, Never>?
}

struct SpaceInsightsView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var duplicateSession: DuplicateScanSession
    @ObservedObject var session: SpaceInsightsSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("空间建议").font(.system(size: 25, weight: .bold))
                    Text("依据已有扫描快照生成，可展开查看依据。全部在本机计算，无需模型，不上传文件。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("更新建议", action: refresh).disabled(session.generating).buttonStyle(.borderedProminent)
            }
            Text("先在应用缓存、大文件和重复文件页面完成扫描。缓存增长需要两次相同规则下的完整扫描。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if session.generating { ProgressView("正在生成本地建议…") }
            if let generatedAt = session.generatedAt { Text("生成于 \(generatedAt.formatted())；扫描更新后请重新生成。") .font(.system(size: 12)).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if session.insights.isEmpty, !session.generating { Text("当前没有足够数据生成建议，请先完成相关扫描。") .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 30) }
                    ForEach(session.insights) { insight in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(insight.title).font(.system(size: 16, weight: .semibold))
                                Spacer()
                                Text("逻辑大小 " + FileSizeFormatter.string(fromByteCount: insight.logicalBytes)).font(.system(size: 12)).monospacedDigit()
                            }
                            Text(insight.detail).font(.system(size: 13)).foregroundStyle(.secondary)
                            DisclosureGroup("查看依据与路径") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(insight.evidence.enumerated()), id: \.offset) { _, text in Text(text).font(.system(size: 12)).textSelection(.enabled) }
                                    ForEach(insight.paths, id: \.self) { path in
                                        HStack {
                                            Text(path).font(.system(size: 12)).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                                            Spacer()
                                            Button("在 Finder 中查看") { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") }
                                        }
                                    }
                                }.padding(.top, 6)
                            }.font(.system(size: 12))
                        }.padding(16).gradientGlass(cornerRadius: 14)
                    }
                }
            }
        }.padding(24).onDisappear { session.work?.cancel() }
    }
    private func refresh() {
        let results = viewModel.scanResults
        let comparison = viewModel.applicationCacheComparison
        let groups = duplicateSession.isLoading ? [] : duplicateSession.groups
        session.generating = true
        session.work = Task {
            let generated = await ScanTask.run { LocalSpaceInsights.build(results: results, comparison: comparison, duplicates: groups) }
            if !Task.isCancelled { session.insights = generated; session.generatedAt = Date() }
            session.generating = false
        }
    }
}
