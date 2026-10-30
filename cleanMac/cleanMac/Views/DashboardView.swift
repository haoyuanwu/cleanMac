import SwiftUI

/// 单一主流程：开始扫描 → 扫描 → 智能一键清理；高级扫描保留为次要操作。
struct DashboardView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var duplicateSession: DuplicateScanSession
    @ObservedObject var xcodeViewModel: XcodeAnalysisViewModel
    let isDeepSearching: Bool
    let deepSearchStage: String
    let deepSearchStep: Int
    let hasCompletedDeepSearch: Bool
    let onDeepSearch: () -> Void
    let onCancelDeepSearch: () -> Void
    let openInsights: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scanning: Bool { viewModel.isScanning || isDeepSearching }
    private var heroPhase: DashboardHeroPhase {
        if scanning { return .scanning }
        if viewModel.isCleaning { return .cleaning }
        return scanFinished ? .finished : .ready
    }
    private var phaseMotion: Animation? {
        reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.9)
    }
    private var stateTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity.animation(.easeOut(duration: 0.12)))
    }
    private var busy: Bool { viewModel.isScanning || isDeepSearching || viewModel.isCleaning }
    private var scanFinished: Bool {
        !busy && viewModel.overviewScanIsComplete && ScanCategory.overviewScanCategories.allSatisfy {
            viewModel.scanResults[$0]?.diagnostics?.status != .cancelled
        }
    }
    private var hasRecommendation: Bool { !viewModel.smartCleanPlan.isEmpty }
    private var hasReadIssues: Bool {
        ScanCategory.overviewScanCategories.contains {
            guard let result = viewModel.scanResults[$0] else { return false }
            return result.error != nil || result.diagnostics?.status == .partial
        }
    }
    private var progress: Double {
        guard isDeepSearching else { return viewModel.overallProgress }
        let count = Double(ScanCategory.allCases.count)
        switch deepSearchStep {
        case 0: return viewModel.overallProgress * count / (count + 2)
        case 1: return count / (count + 2)
        default: return (count + 1) / (count + 2)
        }
    }
    private var headline: String {
        if isDeepSearching { return "正在深度扫描" }
        if viewModel.isScanning { return "正在扫描" }
        if viewModel.isCleaning { return "正在清理" }
        if scanFinished {
            if hasRecommendation { return "发现推荐项目" }
            return viewModel.totalCleanedSize > 0 ? "清理已完成" : "暂无推荐项"
        }
        return "开始扫描"
    }
    private var artworkSubtitle: String {
        if isDeepSearching { return deepSearchStage }
        if scanning { return "" }
        if viewModel.isCleaning { return "正在处理所选项目" }
        if scanFinished { return hasRecommendation ? "推荐项目 · 逻辑大小" : "可以再做一次深度扫描" }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("一键清理").font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                if scanFinished {
                    Button("重新扫描") { startScan() }.buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                }
            }.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 8)
            ChargeReminderBanner(horizontalPadding: 28)
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 20) {
                        Spacer(minLength: 8)
                        hero(viewport: viewport.size)
                        secondaryActions
                        Spacer(minLength: 8)
                    }
                    .frame(maxWidth: 680)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height)
                }
            }
        }
        .animation(phaseMotion, value: heroPhase)
    }

    private var activeScanPath: String? {
        ScanCategory.allCases.compactMap { category -> String? in
            guard let result = viewModel.scanResults[category], result.isScanning,
                  let path = result.diagnostics?.currentPath, !path.isEmpty else { return nil }
            return path
        }.first
    }

    private func hero(viewport: CGSize) -> some View {
        VStack(spacing: scanFinished ? 12 : 18) {
            DashboardHeroArtwork(phase: heroPhase, availableSize: viewport,
                                 title: headline, subtitle: artworkSubtitle,
                                 recommendation: scanFinished && hasRecommendation ? viewModel.smartCleanPlan.totalSizeFormatted : nil,
                                 disabled: busy || (scanFinished && !hasRecommendation),
                                 onActivate: {
                                     if scanFinished { viewModel.requestSmartClean() } else { startScan() }
                                 })
            if scanning {
                Text(activeScanPath ?? "正在准备扫描路径…").font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 500, minHeight: 18)
                    .help(activeScanPath ?? "正在准备扫描路径…")
                    .transition(stateTransition)
            }
            if viewModel.isCleaning {
                ProgressView("正在清理…").transition(.opacity)
            } else if scanning {
                DashboardScanProgress(progress: progress) {
                    if isDeepSearching { onCancelDeepSearch() } else { viewModel.cancelScanAll() }
                }.transition(stateTransition)
            }
            if scanFinished && hasReadIssues {
                Label("部分位置未读全，请在清单中核对", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
            }
        }.frame(maxWidth: .infinity)
    }

    private var secondaryActions: some View {
        VStack(spacing: 16) {
            if !busy {
                Button(action: onDeepSearch) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(.indigo)
                            .frame(width: 40, height: 40).background(Color.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("深度扫描清理").font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                            Text(hasCompletedDeepSearch ? "已完成，可到对应模块查看" : "大文件、重复文件与开发数据")
                                .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.navigationSecondary)
                    }.padding(15).frame(maxWidth: .infinity)
                        .gradientGlass(cornerRadius: 16)
                }
                .transition(stateTransition)
                .buttonStyle(WorkspacePressStyle())
                .disabled(duplicateSession.isLoading || xcodeViewModel.isScanning)
            }
            if scanFinished {
                Button(action: openInsights) {
                    Label("查看空间建议", systemImage: "lightbulb")
                        .font(.system(size: 13, weight: .medium))
                }.buttonStyle(.plain).foregroundStyle(Theme.navigationSecondary)
            }
        }.frame(maxWidth: 480)
    }
    private func startScan() { Task { await viewModel.scanAll() } }
}
