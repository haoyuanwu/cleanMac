import SwiftUI

/// 概览页：大圆环主交互（存储 / 进度 / 可清理构成）+ 精简存储信息
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
    let openDuplicates: () -> Void
    let openXcode: () -> Void
    @State private var appearProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ChargeReminderBanner(horizontalPadding: 32)
                .frame(maxWidth: 920)
            ScrollView {
                VStack(spacing: 0) {
                    // 上：关键指标横排
                    topMetrics
                        .padding(.bottom, 8)

                    // 中：圆环居中
                    ringStage
                        .padding(.vertical, 8)

                    // 下：智能清理 + 构成
                    bottomPanel
                        .padding(.top, 8)

                    if hasDeepResults {
                        deepResultsSection
                            .padding(.top, 20)
                    }

                    if viewModel.hasOverviewScan {
                        treemapSection
                            .padding(.top, 8)
                    }

                    if viewModel.isScanning || isDeepSearching {
                        segmentedProgress
                            .frame(maxWidth: 480)
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 40)
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
                .opacity(appearProgress)
                .offset(y: (1 - appearProgress) * 10)
            }
            .onAppear {
                withAnimation(Theme.easeSlow) { appearProgress = 1 }
            }
        }
    }

    private var deepCleanEntry: some View {
        let isUnavailable = viewModel.isScanning || viewModel.isCleaning
            || duplicateSession.isLoading || xcodeViewModel.isScanning

        return HStack(spacing: 8) {
            if isDeepSearching {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(deepSearchStage)
                Text("深度清理中")
                    .font(.system(size: 12, weight: .semibold))
                Button("取消", action: onCancelDeepSearch)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("取消深度清理")
            } else {
                Button(action: onDeepSearch) {
                    Label("深度清理", systemImage: "sparkle.magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(isUnavailable)
                .opacity(isUnavailable ? 0.5 : 1)
                .help("扫描文件整理、重复文件、应用与 Xcode 数据")
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.accentGradient, in: Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.26), lineWidth: 1)
        )
        .cardShadow()
    }

    // MARK: - 上：指标横排
    private var topMetrics: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("存储空间")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accentGradient)
                    .textCase(.uppercase)
                    .kerning(0.5)
                if let storage = viewModel.storageInfo {
                    Text(storage.volumeName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                Spacer()
            }

            if let storage = viewModel.storageInfo {
                HStack(spacing: 12) {
                    MetricTile(
                        title: "已使用",
                        value: storage.usedFormatted,
                        subtitle: "占用 \(Int(storage.usedPercentage * 100))%",
                        gradient: Theme.accentGradient,
                        compact: true
                    )
                    MetricTile(
                        title: "可用",
                        value: storage.freeFormatted,
                        subtitle: "总容量 \(storage.totalFormatted)",
                        gradient: Theme.successGradient,
                        compact: true
                    )
                    if viewModel.hasOverviewScan {
                        MetricTile(
                            title: "预计可释放",
                            value: viewModel.totalCleanableSizeFormatted,
                            subtitle: "占已用 \(cleanableShareText) · \(viewModel.totalFileCount) 项",
                            gradient: Theme.warmGradient,
                            compact: true
                        )
                        .id(viewModel.totalCleanableSize)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .animation(Theme.easeSlow, value: viewModel.totalCleanableSize)
                    }
                }
            } else {
                ProgressView("读取存储…")
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 中：圆环舞台
    private var ringStage: some View {
        VStack(spacing: 12) {
            ScanHeroControl(
                phase: scanPhase,
                storageUsed: viewModel.storageInfo?.usedPercentage ?? 0,
                storageUsedText: viewModel.storageInfo?.usedFormatted ?? "",
                storageTotalText: viewModel.storageInfo?.totalFormatted ?? "",
                segments: ringSegments,
                cleanableText: showingDeepResults ? "开始清理" : (viewModel.hasOverviewScan ? viewModel.totalCleanableSizeFormatted : ""),
                smartCleanText: viewModel.smartCleanPlan.totalSizeFormatted,
                scanningTitle: isDeepSearching ? "正在深度清理…" : nil,
                scanningSubtitle: isDeepSearching ? deepSearchStage : nil,
                finishedTitle: showingDeepResults ? "深度清理发现" : nil,
                finishedSubtitle: showingDeepResults ? "外环为深度清理发现 · 悬停查看 · 点按进入" : nil,
                isEnabled: !isDeepSearching && !viewModel.isScanning && !viewModel.isCleaning,
                isSmartCleanEnabled: !viewModel.smartCleanPlan.isEmpty && !isDeepSearching && !viewModel.isScanning && !viewModel.isCleaning,
                action: {
                    Task { await viewModel.scanAll() }
                },
                onSmartClean: { viewModel.requestSmartClean() },
                onSegmentTap: { segment in
                    guard segment.id != "other" else { return }
                    if segment.id == "duplicates" { openDuplicates(); return }
                    if segment.id == "xcode" { openXcode(); return }
                    if let category = ScanCategory.allCases.first(where: { $0.id == segment.id }) {
                        withAnimation(Theme.spring) {
                            viewModel.selectedCategory = category
                        }
                    }
                }
            )
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                deepCleanEntry
                    .padding(.top, 42)
                    .padding(.trailing, 8)
            }

            if viewModel.isScanning && !isDeepSearching {
                Button("取消扫描") { viewModel.cancelScanAll() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - 下：智能清理 + 构成图例
    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(viewModel.hasOverviewScan
                     ? (showingDeepResults ? "常规清理结果" : "垃圾清理结果 · 与环上扇区对应")
                     : "清理扫描范围")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            if viewModel.hasOverviewScan {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 10) {
                    ForEach(overviewRingSegments) { segment in
                        legendCard(
                            color: segment.color,
                            name: segment.name,
                            value: segment.detail,
                            percent: segment.percentText
                        ) {
                            guard segment.id != "other" else { return }
                            if let category = ScanCategory.allCases.first(where: { $0.id == segment.id }) {
                                withAnimation(Theme.spring) {
                                    viewModel.selectedCategory = category
                                }
                            }
                        }
                    }
                }

                if !viewModel.isScanning && !viewModel.overviewScanIsComplete {
                    Text("当前仅汇总已扫描类别；点按圆环可补齐全部清理扫描结果。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 10) {
                    ForEach(ScanCategory.overviewScanCategories) { category in
                        legendCard(
                            color: category.color,
                            name: category.rawValue,
                            value: "待扫描",
                            percent: nil,
                            action: nil
                        )
                    }
                }

                Text("打开应用仅静默读取磁盘容量。深度清理可扫描文件整理、重复文件、应用程序与 Xcode 数据；磁盘地图仍在对应模块按需分析。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hasDeepResults: Bool {
        [.downloads, .largeFiles, .installers, .applications].contains { viewModel.scanResults[$0] != nil }
            || duplicateSession.hasScanned || xcodeViewModel.result != nil
    }

    private var deepResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("深度清理发现")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accentGradient)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 10) {
                ForEach([ScanCategory.downloads, .largeFiles, .installers, .applications]) { category in
                    if let result = viewModel.scanResults[category], !result.isScanning {
                        legendCard(
                            color: category.color,
                            name: category.rawValue,
                            value: result.totalSizeFormatted,
                            percent: "\(result.itemCount) 项"
                        ) {
                            viewModel.selectedCategory = category
                        }
                    }
                }

                if duplicateSession.hasScanned && !duplicateSession.isLoading {
                    legendCard(
                        color: .orange,
                        name: "重复文件",
                        value: FileSizeFormatter.string(fromByteCount: duplicateSession.totalWasted),
                        percent: "\(duplicateSession.groups.count) 组冗余",
                        action: openDuplicates
                    )
                }

                if let result = xcodeViewModel.result, !xcodeViewModel.isScanning {
                    legendCard(
                        color: .indigo,
                        name: "Xcode 分析",
                        value: FileSizeFormatter.string(fromByteCount: result.totalSize),
                        percent: "\(result.artifacts.count) 项占用",
                        action: openXcode
                    )
                }
            }

            Text("文件整理、应用和 Xcode 显示发现的占用；重复文件显示保留一份后可释放的冗余空间。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Treemap
    private var treemapSection: some View {
        let nodes = overviewRingSegments.map {
            TreemapNode(id: $0.id, name: $0.name, size: Int64(Double(viewModel.totalCleanableSize) * $0.fraction), color: $0.color)
        }
        let root = TreemapNode(
            id: "root",
            name: "可清理",
            size: viewModel.totalCleanableSize,
            color: .accentColor,
            children: nodes
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("磁盘占用 · Treemap")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("点按块可进入类别")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }

            if nodes.isEmpty {
                Text("暂无可展示数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                TreemapView(root: root) { node in
                    guard node.id != "other" else { return }
                    if let category = ScanCategory.allCases.first(where: { $0.id == node.id }) {
                        withAnimation(Theme.spring) {
                            viewModel.selectedCategory = category
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private func legendCard(
        color: Color,
        name: String,
        value: String,
        percent: String?,
        action: (() -> Void)? = nil
    ) -> some View {
        let content = HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 8, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(percent ?? "")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )

        if let action {
            return AnyView(
                Button(action: action) { content }
                    .buttonStyle(.plain)
            )
        }
        return AnyView(content)
    }

    private var overviewRingSegments: [ScanHeroControl.Segment] {
        let results = ScanCategory.overviewScanCategories.compactMap { category -> (ScanCategory, ScanResult)? in
            guard let result = viewModel.scanResults[category], result.totalSize > 0, !result.isCleaned else {
                return nil
            }
            return (category, result)
        }
        let total = results.reduce(Int64(0)) { $0 + $1.1.totalSize }
        guard total > 0 else { return [] }

        // 小扇区合并为「其他」，避免环上点不中
        let minRatio = 0.03
        var mains: [(ScanCategory, ScanResult, Double)] = []
        var otherSize: Int64 = 0
        var otherCount = 0

        for (category, result) in results {
            let ratio = Double(result.totalSize) / Double(total)
            if ratio >= minRatio {
                mains.append((category, result, ratio))
            } else {
                otherSize += result.totalSize
                otherCount += 1
            }
        }

        var segments = mains.map { category, result, ratio in
            ScanHeroControl.Segment(
                id: category.id,
                name: category.rawValue,
                color: category.color,
                fraction: ratio,
                detail: result.totalSizeFormatted,
                iconAsset: category.iconAsset,
                usesAssetIcon: true
            )
        }

        if otherSize > 0 {
            segments.append(
                ScanHeroControl.Segment(
                    id: "other",
                    name: "其他",
                    color: Color.secondary.opacity(0.55),
                    fraction: Double(otherSize) / Double(total),
                    detail: FileSizeFormatter.string(fromByteCount: otherSize),
                    iconAsset: "square.grid.2x2.fill",
                    usesAssetIcon: false
                )
            )
        }
        return segments
    }

    private var showingDeepResults: Bool {
        hasCompletedDeepSearch && !isDeepSearching && !viewModel.isScanning
            && viewModel.lastCompletedScanScope == .deep
    }

    private var ringSegments: [ScanHeroControl.Segment] {
        guard showingDeepResults else { return overviewRingSegments }

        var findings: [(id: String, name: String, color: Color, size: Int64, icon: String, asset: Bool)] = []
        for category in [ScanCategory.downloads, .installers, .applications] {
            guard let result = viewModel.scanResults[category], !result.isScanning,
                  !result.isCleaned, result.totalSize > 0 else { continue }
            findings.append((category.id, category.rawValue, category.color,
                             result.totalSize, category.iconAsset, true))
        }
        if duplicateSession.hasScanned && !duplicateSession.isLoading && duplicateSession.totalWasted > 0 {
            findings.append(("duplicates", "重复文件", .orange,
                             duplicateSession.totalWasted, "doc.on.doc.fill", false))
        }
        if let result = xcodeViewModel.result, !xcodeViewModel.isScanning && result.totalSize > 0 {
            findings.append(("xcode", "Xcode 分析", .indigo,
                             result.totalSize, "hammer.fill", false))
        }

        let total = findings.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0 else { return [] }
        return findings.map { finding in
            ScanHeroControl.Segment(
                id: finding.id,
                name: finding.name,
                color: finding.color,
                fraction: Double(finding.size) / Double(total),
                detail: FileSizeFormatter.string(fromByteCount: finding.size),
                iconAsset: finding.icon,
                usesAssetIcon: finding.asset
            )
        }
    }

    private var deepScanProgress: Double {
        let categoryCount = Double(ScanCategory.allCases.count)
        let totalSteps = categoryCount + 2
        switch deepSearchStep {
        case 0: return viewModel.overallProgress * categoryCount / totalSteps
        case 1: return categoryCount / totalSteps
        default: return (categoryCount + 1) / totalSteps
        }
    }

    private var scanPhase: ScanHeroControl.Phase {
        if isDeepSearching {
            return .scanning(progress: deepScanProgress)
        }
        if viewModel.isScanning {
            return .scanning(progress: viewModel.overallProgress)
        }
        if viewModel.hasOverviewScan || showingDeepResults {
            return .finished
        }
        return .idle
    }

    private var cleanableShareText: String {
        guard let storage = viewModel.storageInfo, storage.usedBytes > 0 else { return "0.0%" }
        let share = Double(viewModel.totalCleanableSize) / Double(storage.usedBytes)
        return String(format: "%.1f%%", share * 100)
    }

    private var segmentedProgress: some View {
        let categories = isDeepSearching ? ScanCategory.allCases : ScanCategory.overviewScanCategories
        let progress = isDeepSearching ? deepScanProgress : viewModel.overallProgress
        let stepCount = categories.count + (isDeepSearching ? 2 : 0)
        return HStack(spacing: 4) {
            ForEach(0..<stepCount, id: \.self) { index in
                let color = index < categories.count
                    ? categories[index].color
                    : (index == categories.count ? Color.orange : Color.indigo)
                let threshold = Double(index + 1) / Double(stepCount)
                Capsule()
                    .fill(progress >= threshold
                          ? color
                          : Color.primary.opacity(0.08))
                    .frame(height: 5)
                    .animation(Theme.ease, value: progress)
            }
        }
    }
}
