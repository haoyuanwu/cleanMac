import SwiftUI
import Charts

struct TelemetryMetric: View {
    let title: String
    let value: String
    var tint: Color = .indigo
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(tint)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct TelemetryLine: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let series: String
}
struct TelemetryChart: View {
    let values: [TelemetryLine]
    var unit = "%"
    var upper: Double? = nil
    var body: some View {
        Group {
            if values.count < 2 {
                ContentUnavailableTelemetry(text: "正在积累趋势数据…")
            } else {
                Chart(values) { point in
                    LineMark(x: .value("时间", point.date), y: .value(unit, point.value))
                        .foregroundStyle(by: .value("指标", point.series))
                }
                .chartForegroundStyleScale(range: [.indigo, .cyan, .pink])
                .chartYScale(domain: 0...max(upper ?? ((values.map(\.value).max() ?? 1) * 1.15), 1))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute().second()) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                .chartLegend(position: .bottom, alignment: .leading)
                .accessibilityLabel("\(unit)随时间变化，\(values.count)个数据点")
            }
        }.frame(height: 170)
    }
}
struct ContentUnavailableTelemetry: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
            .frame(maxWidth: .infinity, minHeight: 90)
    }
}
struct TelemetryPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).gradientGlass(cornerRadius: 18)
    }
}
func telemetryBytes(_ value: UInt64?) -> String {
    value.map { FileSizeFormatter.string(fromByteCount: Int64(clamping: $0)) } ?? "未读取"
}
