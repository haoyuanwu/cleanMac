import SwiftUI

/// 概览页：大圆环主交互（存储 / 进度 / 可清理构成）+ 精简存储信息
struct DashboardView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var appearProgress: CGFloat = 0

    var body: some View {
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

                if viewModel.hasScanned {
                    treemapSection
                        .padding(.top, 8)
                }

                if viewModel.isScanning {
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
                    if viewModel.hasScanned {
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
                cleanableText: viewModel.hasScanned ? viewModel.totalCleanableSizeFormatted : "",
                isEnabled: !viewModel.isScanning && !viewModel.isCleaning,
                action: {
                    Task { await viewModel.scanAll() }
                },
                onSegmentTap: { segment in
                    guard segment.id != "other" else { return }
                    if let category = ScanCategory.allCases.first(where: { $0.id == segment.id }) {
                        withAnimation(Theme.spring) {
                            viewModel.selectedCategory = category
                        }
                    }
                }
            )
            .frame(maxWidth: .infinity)

            if viewModel.isScanning {
                scanningNote
                    .frame(maxWidth: 360)

                Button("取消扫描") {
                    viewModel.cancelScanAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - 下：智能清理 + 构成图例
    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(viewModel.hasScanned ? "可清理构成 · 与环上扇区对应" : "空间分布（估算）")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if viewModel.hasScanned {
                    smartCleanButton
                }
            }

            if viewModel.hasScanned {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 10) {
                    ForEach(ringSegments) { segment in
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
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 10) {
                    ForEach(viewModel.storageBreakdown.filter { $0.size > 0 }) { cat in
                        legendCard(
                            color: cat.color,
                            name: cat.name,
                            value: cat.sizeFormatted,
                            percent: nil,
                            action: nil
                        )
                    }
                }
            }
        }
    }

    private var smartCleanButton: some View {
        let plan = viewModel.smartCleanPlan
        return Button {
            viewModel.requestSmartClean()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                Text(plan.isEmpty ? "暂无推荐清理" : "智能清理 \(plan.totalSizeFormatted)")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(plan.isEmpty ? AnyShapeStyle(Color.secondary.opacity(0.5)) : AnyShapeStyle(Theme.accentGradient))
            )
        }
        .buttonStyle(.plain)
        .disabled(plan.isEmpty || viewModel.isScanning || viewModel.isCleaning)
        .help("仅清理低风险推荐项（缓存/日志等）")
    }

    // MARK: - Treemap
    private var treemapSection: some View {
        let nodes = ringSegments.map {
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

    private var ringSegments: [ScanHeroControl.Segment] {
        let results = ScanCategory.allCases.compactMap { category -> (ScanCategory, ScanResult)? in
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

    private var scanPhase: ScanHeroControl.Phase {
        if viewModel.isScanning {
            return .scanning(progress: viewModel.overallProgress)
        }
        if viewModel.hasScanned {
            return .finished
        }
        return .idle
    }

    private var cleanableShare: Double {
        guard let storage = viewModel.storageInfo, storage.usedBytes > 0 else { return 0 }
        return Double(viewModel.totalCleanableSize) / Double(storage.usedBytes)
    }

    private var cleanableShareText: String {
        String(format: "%.1f%%", cleanableShare * 100)
    }

    private var scanningNote: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.6)
            Text("全局扫描进行中，暂不可再次扫描")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var segmentedProgress: some View {
        HStack(spacing: 4) {
            ForEach(Array(ScanCategory.allCases.enumerated()), id: \.element) { index, category in
                let threshold = Double(index + 1) / Double(ScanCategory.allCases.count)
                Capsule()
                    .fill(viewModel.overallProgress >= threshold
                          ? category.color
                          : Color.primary.opacity(0.08))
                    .frame(height: 5)
                    .animation(Theme.ease, value: viewModel.overallProgress)
            }
        }
    }
}
