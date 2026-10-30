import SwiftUI

/// 设备信息中的独立应用占用页面，采样不受异常提醒开关影响。
struct ApplicationResourceView: View {
    @ObservedObject private var monitor = HighResourceMonitor.shared
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DeviceFeatureHeader(destination: .page(.applicationUsage), isRefreshing: monitor.isSampling) {
                        monitor.refresh()
                    }
                    ApplicationResourceCard(listHeight: max(260, geometry.size.height - 300), showsHeader: false)
                }
                .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 28)
                .frame(maxWidth: 1080).frame(maxWidth: .infinity)
            }
        }
    }
}

/// 应用占用表格，可适应独立功能页的可用高度。
struct ApplicationResourceCard: View {
    var listHeight: CGFloat = 240
    var showsHeader = true
    @ObservedObject private var monitor = HighResourceMonitor.shared
    @State private var observerID = UUID()
    @State private var query = ""
    @State private var selectedApp: ResourceAppDescriptor?
    @State private var order: Order = .cpu
    private enum Order: String, CaseIterable { case cpu = "CPU"; case memory = "内存"; case name = "名称" }
    private var rows: [ApplicationResourceUsage] {
        monitor.allApplications.filter {
            query.isEmpty || $0.application.name.localizedCaseInsensitiveContains(query)
                || $0.application.bundleID.localizedCaseInsensitiveContains(query)
        }.sorted { lhs, rhs in
            if order != .name && lhs.sampleAvailable != rhs.sampleAvailable { return lhs.sampleAvailable }
            switch order {
            case .cpu:
                if lhs.cpuPercent != rhs.cpuPercent { return (lhs.cpuPercent ?? -1) > (rhs.cpuPercent ?? -1) }
            case .memory:
                if lhs.memory != rhs.memory { return lhs.memory > rhs.memory }
            case .name: break
            }
            return (lhs.application.name, lhs.id) < (rhs.application.name, rhs.id)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                HStack(spacing: 10) {
                    Image(systemName: "app.badge").foregroundStyle(.indigo).accessibilityHidden(true)
                    Text("应用占用").font(.system(size: 15, weight: .semibold))
                    Text("\(monitor.allApplications.count) 个运行应用").font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                    Spacer(minLength: 8)
                    if monitor.isSampling { ProgressView().controlSize(.small).accessibilityLabel("正在更新应用占用") }
                    Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).disabled(monitor.isSampling).help("刷新应用占用").accessibilityLabel("刷新应用占用")
                }
            } else {
                HStack {
                    Text("\(monitor.allApplications.count) 个运行应用")
                    Spacer()
                    if let date = monitor.sampledAt { Text("更新于 " + date.formatted(date: .omitted, time: .standard)) }
                }.font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
            }
            HStack(spacing: 12) {
                TextField("搜索应用", text: $query).textFieldStyle(.plain)
                    .font(.system(size: 12)).padding(8).gradientGlass(cornerRadius: 9)
                Picker("排序", selection: $order) {
                    ForEach(Order.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.font(.system(size: 12)).frame(width: 145)
            }
            HStack {
                Text("应用")
                Spacer()
                Text("CPU").frame(width: 70, alignment: .trailing)
                Text("内存").frame(width: 90, alignment: .trailing)
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.navigationSecondary).padding(.horizontal, 8)
            ScrollView {
                LazyVStack(spacing: 2) {
                    if rows.isEmpty {
                        Text(monitor.isSampling ? "正在读取运行应用…" : query.isEmpty ? "当前未取得运行应用，请刷新重试。" : "没有匹配的应用")
                            .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                            .frame(maxWidth: .infinity, minHeight: 70)
                    }
                    ForEach(rows) { usage in
                        Button { selectedApp = usage.application } label: {
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: usage.application.path))
                                .resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(usage.application.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(usage.sampleAvailable ? "\(usage.processCount) 个关联进程" : "占用数据未能读取")
                                    .font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(usage.sampleAvailable ? usage.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "采样中" : "未读取")
                                .frame(width: 70, alignment: .trailing)
                            Text(usage.sampleAvailable ? FileSizeFormatter.string(fromByteCount: Int64(clamping: usage.memory)) : "未读取")
                                .frame(width: 90, alignment: .trailing)
                        }.font(.system(size: 12)).monospacedDigit().padding(.horizontal, 8).padding(.vertical, 6)
                        }.buttonStyle(WorkspacePressStyle())
                            .accessibilityLabel("查看\(usage.application.name)的占用详情")
                            .contextMenu {
                                Button("查看占用详情") { selectedApp = usage.application }
                                Button(monitor.ignoredBundleIDs.contains(usage.application.bundleID) ? "恢复异常提醒" : "忽略异常提醒") {
                                    monitor.setIgnored(usage.application, ignored: !monitor.ignoredBundleIDs.contains(usage.application.bundleID))
                                }
                                Button("在 Finder 中显示") { NSWorkspace.shared.selectFile(usage.application.path, inFileViewerRootedAtPath: "") }
                            }
                    }
                }
            }.frame(height: listHeight)
            Text("每 5 秒更新 · CPU 100% 约为一个核心 · 内存为可读取关联进程的合计估算")
                .font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
        }.padding(18).gradientGlass(cornerRadius: 18)
            .onAppear { monitor.retainOverview(observerID) }
            .onDisappear { monitor.releaseOverview(observerID) }
            .sheet(item: $selectedApp) { ApplicationUsageDetailView(app: $0) }
    }
}
