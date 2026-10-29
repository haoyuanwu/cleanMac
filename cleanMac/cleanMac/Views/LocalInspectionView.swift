import SwiftUI
import Combine

@MainActor
final class LocalInspectionSession: ObservableObject {
    @Published var report: InspectionReport?
    @Published var loading = false
    @Published var includeAppleServices = false
    var scanTask: Task<Void, Never>?
}

struct LocalInspectionView: View {
    enum Kind { case startup, privacy, extensions }
    let kind: Kind
    @ObservedObject var session: LocalInspectionSession
    @State private var query = ""
    @State private var owner = "全部"
    @State private var statusMessage: String?
    @State private var pendingStartup: InspectionItem?
    @State private var pendingEnabled = false
    @State private var changingID: String?

    private var title: String { switch kind { case .startup: "启动项检查"; case .privacy: "浏览器隐私清单"; case .extensions: "扩展与插件" } }
    private var symbol: String { switch kind { case .startup: "power"; case .privacy: "hand.raised"; case .extensions: "puzzlepiece.extension" } }
    private var tint: Color { switch kind { case .startup: .purple; case .privacy: .blue; case .extensions: .indigo } }
    private var subtitle: String {
        switch kind {
        case .startup: "查看软件的登录与后台启动项，核对来源并管理启动策略。"
        case .privacy: "查看历史、下载记录及 Cookie 文件的元数据；清除它们可能退出登录或丢失历史。"
        case .extensions: "按所属软件盘点浏览器、编辑器和音频插件，查看版本与占用。"
        }
    }
    private var filtered: [InspectionItem] {
        (session.report?.items ?? []).filter { (owner == "全部" || $0.softwareName == owner)
            && (query.isEmpty || [$0.name, $0.softwareName, $0.owner, $0.path, $0.kind].contains { $0.localizedCaseInsensitiveContains(query) }) }
            .sorted {
                if ($0.application != nil) != ($1.application != nil) { return $0.application != nil }
                return ($0.softwareName, $0.name, $0.path) < ($1.softwareName, $1.name, $1.path)
            }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(tint)
                    .frame(width: 44, height: 44).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 22, weight: .bold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                }
                Spacer(minLength: 8)
                if kind == .startup { Button("系统登录项设置", action: openSettings) }
                if session.loading { Button("取消扫描") { session.scanTask?.cancel() } }
                else if session.report != nil { Button("重新扫描", action: scan).disabled(changingID != nil) }
            }
            if kind == .startup {
                Toggle("包含 macOS 内置服务（仅查看）", isOn: $session.includeAppleServices)
                    .toggleStyle(.checkbox).font(.system(size: 12)).disabled(session.loading || changingID != nil)
                    .onChange(of: session.includeAppleServices) { _ in session.report = nil }
            }
            if let statusMessage { Text(statusMessage).font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary).textSelection(.enabled) }
            if session.loading {
                VStack(spacing: 18) {
                    ProgressView().controlSize(.large)
                    Text("正在扫描" + title).font(.system(size: 19, weight: .semibold))
                    Text("读取本机信息，不加载插件或启动被扫描的程序。")
                        .font(.system(size: 13)).foregroundStyle(Theme.navigationSecondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let report = session.report {
                HStack {
                    TextField("搜索软件、项目名称或路径", text: $query).textFieldStyle(.plain)
                        .padding(.horizontal, 10).padding(.vertical, 8).gradientGlass(cornerRadius: 10)
                    Picker("所属软件", selection: $owner) {
                        Text("全部").tag("全部")
                        ForEach(Array(Set(report.items.map(\.softwareName))).sorted(), id: \.self) { Text($0).tag($0) }
                    }.frame(maxWidth: 240)
                }
                Text("\(report.cancelled ? "已取消 · 结果不完整" : report.issues.isEmpty ? "扫描完成" : "部分位置未能读取") · \(report.items.count) 个项目 · \(report.scannedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                if !report.issues.isEmpty {
                    DisclosureGroup("查看 \(report.issues.count) 条读取提示") {
                        ScrollView { VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(report.issues.enumerated()), id: \.offset) { _, text in Text(text).textSelection(.enabled) }
                        } }.frame(maxHeight: 100)
                    }.font(.system(size: 12)).foregroundStyle(.orange)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if filtered.isEmpty {
                            Text(query.isEmpty && owner == "全部" ? "当前范围未列出项目；如有读取提示，请先展开核对。" : "没有匹配项，请清除筛选或尝试其他名称。")
                                .font(.system(size: 13)).foregroundStyle(Theme.navigationSecondary).padding(.vertical, 30)
                        }
                        ForEach(filtered) { item in inspectionRow(item) }
                    }
                }
            } else {
                VStack(spacing: 22) {
                    Spacer(minLength: 16)
                    Image(systemName: symbol)
                        .font(.system(size: 46, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 100, height: 100)
                        .background(Theme.categoryGradient(tint), in: RoundedRectangle(cornerRadius: 28))
                        .elevatedShadow().accessibilityHidden(true)
                    VStack(spacing: 10) {
                        Text(title).font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.navigationSecondary)
                            .multilineTextAlignment(.center).frame(maxWidth: 420)
                    }
                    Button(action: scan) {
                        Label("开始扫描", systemImage: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold)).padding(.horizontal, 28).padding(.vertical, 14)
                    }.buttonStyle(GradientButtonStyleCompact())
                    Spacer(minLength: 16)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(kind == .startup ? "仅已确认软件归属的第三方用户 LaunchAgent 可更改下次加载策略；其他启动项在系统设置管理。签名不用于判定恶意。" : "只读检查 · 不加载插件或清除隐私数据 · 不上传本机数据")
                .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
        }.padding(24)
            .onDisappear { session.scanTask?.cancel() }
            .alert("更改启动策略", isPresented: Binding(get: { pendingStartup != nil }, set: { if !$0 { pendingStartup = nil } })) {
                Button("取消", role: .cancel) { pendingStartup = nil }
                Button(pendingEnabled ? "允许下次加载" : "禁止下次加载") {
                    if let item = pendingStartup { changeStartup(item, enabled: pendingEnabled) }
                    pendingStartup = nil
                }
            } message: {
                Text("\(pendingStartup?.application?.name ?? pendingStartup?.name ?? "此项目")：\(pendingEnabled ? "允许" : "禁止")该启动项下次加载。不会停止正在运行的进程，启用也不会立即启动程序。")
            }
    }

    private func inspectionRow(_ item: InspectionItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                InspectionSoftwareIcon(application: item.application, fallback: kind == .privacy ? "globe" : kind == .startup ? "app.badge" : "puzzlepiece.extension")
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.application?.name ?? (kind == .startup ? item.name : item.softwareName))
                        .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(kind == .startup && item.application == nil ? "所属软件待确认 · " + item.kind : item.name + " · " + item.kind)
                        .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                if kind == .startup {
                    if let enabled = item.startupEnabled {
                        VStack(alignment: .trailing, spacing: 4) {
                            Toggle("下次加载", isOn: Binding(get: { enabled }, set: { next in pendingEnabled = next; pendingStartup = item }))
                                .toggleStyle(.switch).fixedSize()
                                .disabled(!item.startupCanControl || changingID != nil)
                                .accessibilityLabel("\(item.application?.name ?? item.name)的启动加载策略")
                            Text(item.startupCanControl ? "下次加载策略" : (item.application == nil ? "归属待确认" : "受保护"))
                                .font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
                        }
                    } else { Text("状态待核对").font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary) }
                    if !item.startupCanControl { Button("系统设置", action: openSettings).font(.system(size: 12)) }
                    if changingID == item.id { ProgressView().controlSize(.small) }
                } else if let size = item.size {
                    Text(FileSizeFormatter.string(fromByteCount: size)).font(.system(size: 12)).monospacedDigit()
                } else if kind == .extensions { Text("占用未统计").font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary) }
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    if item.version != "未提供" { detailLine("版本", item.version) }
                    detailLine("来源", item.source)
                    detailLine("路径", item.path)
                    if !item.notes.isEmpty {
                        DisclosureGroup("更多说明") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(item.notes.enumerated()), id: \.offset) { _, note in Text(note).frame(maxWidth: .infinity, alignment: .leading) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                        }.accessibilityLabel("更多说明")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 12)).foregroundStyle(Theme.navigationSecondary)
                    .textSelection(.enabled).padding(.top, 8)
            } label: {
                Text("来源与路径").frame(maxWidth: .infinity, alignment: .leading)
            }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)

        }.padding(16).gradientGlass(cornerRadius: 14)
            .contextMenu {
                Button("在 Finder 中显示") { NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "") }.disabled(!item.path.hasPrefix("/"))
                Button("复制路径") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.path, forType: .string) }
            }
    }
    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).frame(width: 32, alignment: .leading).foregroundStyle(.secondary)
            Text(value.isEmpty ? "未提供" : value)
                .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                .lineLimit(label == "路径" ? 2 : 3).truncationMode(.middle).help(value)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openSettings() {
        if !PrivacySettingsOpener.openLoginItems() { statusMessage = "系统设置未能打开，请手动进入“通用 → 登录项与扩展”。" }
    }
    private func changeStartup(_ item: InspectionItem, enabled: Bool) {
        changingID = item.id
        Task {
            let error = await ScanTask.run { StartupControlService.setEnabled(enabled, item: item) }
            if let error { statusMessage = error }
            else {
                if var report = session.report {
                    for index in report.items.indices where report.items[index].startupLabel == item.startupLabel && report.items[index].startupCanControl {
                        report.items[index].startupEnabled = enabled
                    }
                    session.report = report
                }
                statusMessage = "已更新下次加载策略；正在运行的进程不受影响。"
            }
            changingID = nil
        }
    }
    private func scan() {
        session.loading = true; owner = "全部"; statusMessage = nil
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let includeApple = session.includeAppleServices
        session.scanTask = Task {
            let result = await ScanTask.run {
                switch kind {
                case .startup: StartupInspectionService.scan(includeAppleServices: includeApple)
                case .privacy: BrowserPrivacyService.scan(runningBundleIdentifiers: runningIDs)
                case .extensions: ExtensionInventoryService.scan()
                }
            }
            session.report = result; session.loading = false
        }
    }
}

private struct InspectionSoftwareIcon: View {
    let application: CacheApplication?
    let fallback: String
    @State private var icon: NSImage?
    var body: some View {
        Group {
            if let icon { Image(nsImage: icon).resizable().scaledToFit() }
            else { Image(systemName: fallback).font(.system(size: 27)).foregroundStyle(.secondary) }
        }.frame(width: 44, height: 44).accessibilityHidden(true)
            .task(id: application) { icon = application?.icon }
    }
}
