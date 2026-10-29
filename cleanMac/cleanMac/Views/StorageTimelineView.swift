import SwiftUI

/// 按当天、当周、当月和当年查看磁盘已用空间的变化。
struct StorageTimelineView: View {
    @State private var snapshots: [StorageSnapshot] = []
    @State private var selectedPeriod: StoragePeriod = .today
    @State private var appeared = false

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
                listCard
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 40)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("")

        .task {
            guard !appeared else { return }
            appeared = true
            await reload()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 22))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.accentGradient)
                )
                .elevatedShadow()

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
            }
        }
    }

    private var periodPicker: some View {
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

            HStack(spacing: 4) {
                ForEach(StoragePeriod.allCases) { period in
                    let isSelected = selectedPeriod == period
                    Button {
                        selectedPeriod = period
                    } label: {
                        VStack(spacing: 3) {
                            Text(period.rawValue)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Text(period.bucketDescription)
                                .font(.system(size: 10, weight: .medium))
                                .opacity(isSelected ? 0.85 : 0.65)
                        }
                        .foregroundColor(isSelected ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            isSelected
                                ? AnyShapeStyle(Theme.accentGradient)
                                : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(period.rawValue)，\(period.bucketDescription)")
                    .accessibilityValue(isSelected ? "已选中" : "")
                }
            }
            .padding(4)
            .background(Theme.surfaceSunk, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .padding(16)
        .gradientGlass(cornerRadius: 18)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.cardStroke))
        .cardShadow()
        .animation(Theme.spring, value: selectedPeriod)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            MetricTile(
                title: "\(selectedPeriod.rawValue)最新已用",
                value: periodSnapshots.last?.usedFormatted ?? "—",
                subtitle: "最近一次记录",
                gradient: Theme.accentGradient,
                compact: true
            )
            MetricTile(
                title: "\(selectedPeriod.rawValue)最新可用",
                value: periodSnapshots.last?.freeFormatted ?? "—",
                subtitle: "磁盘剩余空间",
                gradient: Theme.successGradient,
                compact: true
            )
            MetricTile(
                title: "\(selectedPeriod.rawValue)占用变化",
                value: StorageTimeline.delta(periodSamples)?.text ?? "—",
                subtitle: "从首条记录至今",
                gradient: Theme.warmGradient,
                compact: true
            )
        }
    }

    private var chartCard: some View {
        CardView {
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
        let values = periodSnapshots.map { Double($0.usedBytes) / 1_000_000_000 }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let padding = max(0.5, (maximum - minimum) * 0.2)
        let lower = max(0, minimum - padding)
        let upper = maximum + padding
        let span = max(upper - lower, 1)

        return GeometryReader { geometry in
            ZStack {
                ForEach(0..<3) { index in
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 1)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * CGFloat(index) / 2)
                }

                Path { path in
                    for (index, value) in values.enumerated() {
                        let point = chartPoint(index: index, value: value, count: values.count, lower: lower, span: span, size: geometry.size)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(Theme.accentGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                ForEach(Array(periodSnapshots.enumerated()), id: \.offset) { index, snapshot in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .position(chartPoint(
                            index: index,
                            value: values[index],
                            count: values.count,
                            lower: lower,
                            span: span,
                            size: geometry.size
                        ))
                        .help("\(StorageTimeline.label(for: snapshot, period: selectedPeriod)) · \(snapshot.usedFormatted)")
                }
            }
        }
        .frame(height: 190)
        .accessibilityLabel("\(selectedPeriod.rawValue)磁盘已用空间趋势，共 \(periodSnapshots.count) 条记录")
    }

    private func chartPoint(index: Int, value: Double, count: Int, lower: Double, span: Double, size: CGSize) -> CGPoint {
        let x = count == 1 ? size.width / 2 : size.width * CGFloat(index) / CGFloat(count - 1)
        let y = size.height * (1 - CGFloat((value - lower) / span))
        return CGPoint(x: x, y: y)
    }

    private var listCard: some View {
        CardView {
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
        let service = SystemInfoService()
        let storage = await Task.detached { service.getStorageInfo() }.value
        StorageTimeline.record(storage: storage)
        snapshots = StorageTimeline.load()
    }
}
