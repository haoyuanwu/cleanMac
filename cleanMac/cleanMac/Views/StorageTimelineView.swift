import SwiftUI

/// 按当天、当周、当月和当年查看磁盘已用空间的变化。
struct StorageTimelineView: View {
    @ObservedObject private var viewModel = MainViewModel.shared
    @State private var snapshots: [StorageSnapshot] = []
    @State private var selectedPeriod: StoragePeriod = .today
    @State private var appeared = false
    @State private var chartProgress: CGFloat = 0
    @State private var highlightedSnapshot: Date?
    @State private var isRefreshing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var periodSnapshots: [StorageSnapshot] {
        StorageTimeline.snapshots(snapshots, for: selectedPeriod)
    }

    private var periodSamples: [StorageSnapshot] {
        StorageTimeline.samples(snapshots, for: selectedPeriod)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                periodPicker
                summary
                chartCard
                StorageGrowthSourcesView(viewModel: viewModel)
                listCard
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 40)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("")
        .animation(reduceMotion ? nil : Theme.ease, value: selectedPeriod)
        .animation(reduceMotion ? nil : Theme.ease, value: snapshots)
        .task(id: "\(selectedPeriod.rawValue):\(periodSnapshots)") {
            highlightedSnapshot = nil
            guard !reduceMotion else { chartProgress = 1; return }
            chartProgress = 0
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            withAnimation(.easeOut(duration: 0.45)) { chartProgress = 1 }
        }

        .task {
            guard !appeared else { return }
            appeared = true
            await reload()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 22, weight: .semibold))
                .moduleIconPlate(tint: .indigo, size: 48, radius: 14)

            VStack(alignment: .leading, spacing: 4) {
                Text("占用变化")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("按小时、天或月查看磁盘空间变化")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            DetailTextButton(title: "刷新数据", systemImage: "arrow.clockwise") {
                Task { await reload() }
            }.disabled(isRefreshing)
        }
    }

    private var periodPicker: some View {
        StorageTimelinePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accentGradient)

                    Text("统计范围")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))

                    Spacer()

                    Text("\(periodSnapshots.count) 条记录")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accentGradient)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Theme.accentGradientSoft, in: Capsule())
                }

                ChoiceSegments(title: "统计范围", selection: $selectedPeriod,
                               options: StoragePeriod.allCases.map { ChoiceItem(value: $0, title: $0.rawValue, subtitle: $0.bucketDescription) })

            }
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            timelineMetric(
                title: "\(selectedPeriod.rawValue)最新已用",
                value: periodSnapshots.last?.usedFormatted ?? "—",
                subtitle: "最近一次记录",
                gradient: Theme.accentGradient
            )
            timelineMetric(
                title: "\(selectedPeriod.rawValue)最新可用",
                value: periodSnapshots.last?.freeFormatted ?? "—",
                subtitle: "磁盘剩余空间",
                gradient: Theme.successGradient
            )
            timelineMetric(
                title: "\(selectedPeriod.rawValue)占用变化",
                value: StorageTimeline.delta(periodSamples)?.text ?? "—",
                subtitle: "从首条记录至今",
                gradient: Theme.warmGradient
            )
        }
    }

    private var chartCard: some View {
        StorageTimelinePanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("\(selectedPeriod.rawValue)已用空间趋势")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("GB · \(selectedPeriod.bucketDescription)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if periodSnapshots.isEmpty {
                    emptyMessage
                        .frame(maxWidth: .infinity, minHeight: 190)
                } else {
                    trendChart
                    Text("悬停任意一列查看占用 · 支持点击数据点")
                        .font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
                    HStack {
                        Text(periodSnapshots.first.map { StorageTimeline.label(for: $0, period: selectedPeriod) } ?? "")
                        Spacer()
                        Text(periodSnapshots.last.map { StorageTimeline.label(for: $0, period: selectedPeriod) } ?? "")
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private var trendChart: some View {
        let entries = periodSnapshots
        let values = entries.map { Double($0.usedBytes) / 1_000_000_000 }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let padding = max(0.5, (maximum - minimum) * 0.2)
        let lower = max(0, minimum - padding)
        let span = max(maximum + padding - lower, 1)

        return GeometryReader { geometry in
            let size = geometry.size
            let selectedIndex = entries.firstIndex { $0.id == highlightedSnapshot }
            ZStack(alignment: .topLeading) {
                ForEach(0..<3) { index in
                    Rectangle().fill(Theme.actionInk.opacity(0.10)).frame(height: 1)
                        .position(x: size.width / 2, y: size.height * CGFloat(index) / 2)
                }
                if let index = selectedIndex {
                    let point = chartPoint(index: index, value: values[index], count: values.count, lower: lower, span: span, size: size)
                    let halfColumn = values.count > 1 ? size.width / CGFloat(values.count - 1) / 2 : size.width
                    let left = max(0, point.x - halfColumn)
                    let right = min(size.width, point.x + halfColumn)
                    RoundedRectangle(cornerRadius: 6).fill(Theme.actionInk.opacity(0.07))
                        .frame(width: max(0, right - left), height: size.height)
                        .offset(x: left)
                    Path { path in path.move(to: CGPoint(x: point.x, y: 0)); path.addLine(to: CGPoint(x: point.x, y: size.height)) }
                        .stroke(Theme.actionInk.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                Path { path in
                    for (index, value) in values.enumerated() {
                        let point = chartPoint(index: index, value: value, count: values.count, lower: lower, span: span, size: size)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }.trim(from: 0, to: chartProgress)
                    .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, snapshot in
                    let point = chartPoint(index: index, value: values[index], count: values.count, lower: lower, span: span, size: size)
                    let halfColumn = values.count > 1 ? size.width / CGFloat(values.count - 1) / 2 : size.width
                    let left = max(0, point.x - halfColumn)
                    let right = min(size.width, point.x + halfColumn)
                    Circle().fill(Theme.actionAccent)
                        .frame(width: highlightedSnapshot == snapshot.id ? 11 : 6,
                               height: highlightedSnapshot == snapshot.id ? 11 : 6)
                        .overlay(Circle().stroke(Theme.surfaceRaised, lineWidth: highlightedSnapshot == snapshot.id ? 2 : 0))
                        .position(point).opacity(chartProgress).allowsHitTesting(false)
                    Button { selectSnapshot(snapshot.id) } label: {
                        Color.clear.frame(width: max(0, right - left), height: size.height)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering { selectSnapshot(snapshot.id) }
                            else if highlightedSnapshot == snapshot.id { selectSnapshot(nil) }
                        }
                        .position(x: (left + right) / 2, y: size.height / 2)
                        .accessibilityLabel(StorageTimeline.label(for: snapshot, period: selectedPeriod) + "，已用 " + snapshot.usedFormatted + "，可用 " + snapshot.freeFormatted)

                }
                if let index = selectedIndex {
                    let snapshot = entries[index]
                    let point = chartPoint(index: index, value: values[index], count: values.count, lower: lower, span: span, size: size)
                    let bubbleWidth = min(190, size.width)
                    let bubbleX = min(max(bubbleWidth / 2, point.x), size.width - bubbleWidth / 2)
                    let bubbleY = point.y > 100 ? max(44, point.y - 58) : min(size.height - 44, point.y + 58)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.actionInk)
                        HStack { Text("已用").foregroundStyle(Theme.navigationSecondary); Spacer(); Text(snapshot.usedFormatted).fontWeight(.semibold) }
                        HStack { Text("可用").foregroundStyle(Theme.navigationSecondary); Spacer(); Text(snapshot.freeFormatted).fontWeight(.semibold) }
                    }.font(.system(size: 12)).monospacedDigit().padding(12)
                        .frame(width: bubbleWidth)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.actionInk.opacity(0.25)))
                        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
                        .position(x: bubbleX, y: bubbleY)
                        .allowsHitTesting(false).transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
        }.frame(height: 210)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(selectedPeriod.rawValue)磁盘已用空间趋势")
    }

    private func selectSnapshot(_ id: Date?) {
        guard highlightedSnapshot != id else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { highlightedSnapshot = id }
    }

    private func timelineMetric(title: String, value: String, subtitle: String, gradient: LinearGradient) -> some View {
        StorageTimelinePanel(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.navigationSecondary)
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(gradient).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
            }
        }
    }

    private func chartPoint(index: Int, value: Double, count: Int, lower: Double, span: Double, size: CGSize) -> CGPoint {
        let x = count == 1 ? size.width / 2 : size.width * CGFloat(index) / CGFloat(count - 1)
        let y = size.height * (1 - CGFloat((value - lower) / span))
        return CGPoint(x: x, y: y)
    }

    private var listCard: some View {
        StorageTimelinePanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(selectedPeriod.rawValue)记录")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(selectedPeriod.bucketDescription)取最近一次快照")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if periodSnapshots.isEmpty {
                    emptyMessage
                        .frame(maxWidth: .infinity, minHeight: 90)
                } else {
                    ForEach(periodSnapshots.reversed()) { snapshot in
                        HStack(spacing: 12) {
                            Text(StorageTimeline.label(for: snapshot, period: selectedPeriod))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                            Spacer()
                            Text("已用 \(snapshot.usedFormatted)")
                                .font(.caption)
                            Text("可用 \(snapshot.freeFormatted)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(minWidth: 110, alignment: .trailing)
                        }
                        .padding(.vertical, 5)
                        if snapshot.id != periodSnapshots.first?.id { Divider() }
                    }
                }
            }
        }
    }

    private var emptyMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 23))
                .foregroundColor(.secondary)
            Text("\(selectedPeriod.rawValue)暂无记录")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text("应用运行期间会自动记录磁盘占用")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    private func reload() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let service = SystemInfoService()
        let storage = await Task.detached { service.getStorageInfo() }.value
        StorageTimeline.record(storage: storage)
        snapshots = StorageTimeline.load()
    }
}
