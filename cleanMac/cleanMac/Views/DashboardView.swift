import SwiftUI

/// 单一主流程：开始清理 → 扫描 → 智能一键清理；高级扫描保留为次要操作。
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
        if viewModel.isScanning { return "正在查找可清理项目" }
        if viewModel.isCleaning { return "正在清理" }
        if scanFinished {
            if hasRecommendation { return "准备好，轻装出发" }
            return viewModel.totalCleanedSize > 0 ? "清理已完成" : "暂时没有推荐清理项"
        }
        return "让你的 Mac 轻装上阵"
    }
    private var detail: String {
        if isDeepSearching { return deepSearchStage }
        if viewModel.isScanning { return "正在检查缓存、日志与应用残留，请稍候。" }
        if viewModel.isCleaning { return "正在处理你确认的项目，请稍候。" }
        if scanFinished {
            if hasRecommendation { return "已整理低风险推荐项目，确认后即可一键清理。" }
            return "可以重新扫描，或使用深度扫描继续检查其他空间。"
        }
        if viewModel.hasOverviewScan { return "上次检查尚未完成，重新扫描后再确认清理。" }
        return "先查找可清理的缓存与日志，再由你确认处理。"
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
            DashboardHeroArtwork(phase: heroPhase, availableSize: viewport)
            VStack(spacing: 9) {
                Text(headline).font(.system(size: 27, weight: .bold, design: .rounded))
                    .id(headline).transition(stateTransition)
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.navigationSecondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 460)
                    .id(heroPhase).transition(.opacity)
            }
            if scanning {
                Text(activeScanPath ?? "正在准备扫描路径…").font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 500, minHeight: 18)
                    .help(activeScanPath ?? "正在准备扫描路径…")
                    .transition(stateTransition)
            }
            if scanFinished && hasRecommendation {
                VStack(spacing: 4) {
                    Text(viewModel.smartCleanPlan.totalSizeFormatted)
                        .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("推荐项目的逻辑大小").font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                }
            }
            if viewModel.isCleaning {
                ProgressView("正在清理…").transition(.opacity)
            } else {
                DashboardScanControls(scanning: scanning, progress: progress,
                    title: scanFinished ? "智能一键清理" : "开始清理",
                    disabled: scanFinished && !hasRecommendation,
                    onStart: {
                        if scanFinished { viewModel.requestSmartClean() } else { startScan() }
                    }, onCancel: {
                        if isDeepSearching { onCancelDeepSearch() } else { viewModel.cancelScanAll() }
                    })
                    .help(scanning ? "可随时取消扫描" : scanFinished ? "核对推荐项目并确认清理" : "先扫描可清理项目，扫描后确认清理")
            }
            if scanFinished {
                Text(hasReadIssues ? "部分位置未能完整读取，请在确认前核对推荐项目。" : "清理前可核对项目，回收后可在清理记录中恢复。")
                    .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                    .multilineTextAlignment(.center)
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
                            Text(hasCompletedDeepSearch ? "已完成深度扫描，可在对应模块查看和处理" : "进一步检查大文件、重复文件与开发数据")
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
