import AppKit
import SwiftUI
import Combine
import Darwin
import ApplicationServices

@MainActor
final class HighResourceMonitor: ObservableObject {
    static let shared = HighResourceMonitor()
    @Published private(set) var applications: [ApplicationResourceUsage] = []
    @Published private(set) var allApplications: [ApplicationResourceUsage] = []
    @Published private(set) var isSampling = false
    @Published private(set) var sampledAt: Date?
    @Published var message: String?
    @Published private(set) var snoozedUntil: Date?
    private var overviewClients = Set<UUID>()
    private var timer: Timer?
    private var work: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private var previous: [ResourceProcessSample] = []
    private var previousTime: TimeInterval = 0
    private var policy = ResourceAlertPolicy(memoryThreshold: 2 * 1024 * 1024 * 1024)
    private var configuration = ""
    private var generation = 0
    var onAlert: (() -> Void)?
    var onUpdate: (() -> Void)?

    var enabled: Bool { UserDefaults.standard.object(forKey: "com.cleanMac.resourceAlerts") as? Bool ?? true }
    func start() {
        guard subscription == nil else { return }
        subscription = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.configure() }
        configure()
    }
    private func configure() {
        let defaults = UserDefaults.standard
        let cpu = min(800, max(50, defaults.object(forKey: "com.cleanMac.resourceCPUThreshold") as? Double ?? 150))
        let memory = min(50, max(10, defaults.object(forKey: "com.cleanMac.resourceMemoryPercent") as? Double ?? 20))
        let samplingNeeded = enabled || !overviewClients.isEmpty
        let signature = "\(enabled):\(cpu):\(memory):\(samplingNeeded)"
        guard signature != configuration else { return }
        configuration = signature; generation += 1
        timer?.invalidate(); timer = nil; work?.cancel(); work = nil
        applications = []; allApplications = []; isSampling = false; previous = []; previousTime = 0
        policy = ResourceAlertPolicy(cpuThreshold: cpu, memoryThreshold: max(2 * 1024 * 1024 * 1024, UInt64(Double(ProcessInfo.processInfo.physicalMemory) * memory / 100)))
        onUpdate?()
        guard samplingNeeded else { return }
        refresh()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        timer.tolerance = 1; RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func retainOverview(_ id: UUID) { overviewClients.insert(id); start(); configure() }
    func releaseOverview(_ id: UUID) { overviewClients.remove(id); configure() }
    private func canAlert(_ app: ResourceAppDescriptor) -> Bool {
        app.pid != ProcessInfo.processInfo.processIdentifier
            && !app.bundleID.lowercased().hasPrefix("com.cleanmac.")
            && !SafetyWhitelist.isProtectedApp(path: app.path)
            && !app.path.hasPrefix("/System/") && !app.path.hasPrefix("/usr/")
            && !UserWhitelist.isWhitelisted(app.path)
    }
    func refresh() {
        guard enabled || !overviewClients.isEmpty, work == nil else { return }
        isSampling = true
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> ResourceAppDescriptor? in
            guard app.activationPolicy == .regular, !app.isTerminated,
                  let path = app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path, let date = app.launchDate,
                  let id = app.bundleIdentifier else { return nil }
            return ResourceAppDescriptor(pid: app.processIdentifier, launchDate: date, bundleID: id, name: app.localizedName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, path: path)
        }
        let token = generation
        let eligibleIDs = Set(apps.filter(canAlert).map(\.id))
        let checkResponsiveness = enabled && AXIsProcessTrusted()
        work = Task {
            let reading = await ScanTask.run {
                let samples = ApplicationResourceReader.processes()
                var responses: [String: ResourceResponsiveness] = [:]
                if checkResponsiveness {
                    for app in apps where eligibleIDs.contains(app.id) {
                        if Task.isCancelled { break }
                        let element = AXUIElementCreateApplication(app.pid)
                        AXUIElementSetMessagingTimeout(element, 0.25)
                        var value: CFTypeRef?
                        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
                        responses[app.id] = result == .success ? .responsive : result == .cannotComplete ? .unresponsive : .unknown
                    }
                }
                return (samples, responses)
            }
            let samples = reading.0
            guard token == generation, !Task.isCancelled else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let usage = ApplicationResourceReader.aggregate(applications: apps, current: samples, previous: previous, elapsed: now - previousTime).map { original in
                var usage = original
                usage.responsiveness = reading.1[usage.id] ?? .unknown
                return usage
            }
            previous = samples; previousTime = now; sampledAt = Date()
            let alertsAllowed = snoozedUntil.map({ $0 <= Date() }) ?? true
            allApplications = usage.sorted { $0.application.name.localizedStandardCompare($1.application.name) == .orderedAscending }
            let result = policy.evaluate(usage.filter { $0.sampleAvailable && eligibleIDs.contains($0.id) }, now: now, notificationsEnabled: enabled && alertsAllowed)
            applications = enabled ? result.high : []
            if !apps.isEmpty && samples.isEmpty { message = "当前无法读取应用进程占用，请稍后重试。" }
            else if message == "当前无法读取应用进程占用，请稍后重试。" { message = nil }
            work = nil; isSampling = false
            onUpdate?()
            if !result.notify.isEmpty, snoozedUntil.map({ $0 <= Date() }) ?? true { onAlert?() }
        }
    }
    func snooze() { snoozedUntil = Date().addingTimeInterval(30 * 60) }
    func resumeAlerts() { snoozedUntil = nil }

    private func validated(_ target: ResourceAppDescriptor) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated,
              app.launchDate == target.launchDate, app.bundleIdentifier == target.bundleID,
              app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path == target.path, app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !target.bundleID.lowercased().hasPrefix("com.cleanmac."),
              !SafetyWhitelist.isProtectedApp(path: target.path), !target.path.hasPrefix("/System/"),
              !UserWhitelist.isWhitelisted(target.path) else { return nil }
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(target.pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size, bsd.pbi_uid == getuid() else { return nil }
        return app
    }
    func end(_ target: ResourceAppDescriptor, force: Bool) {
        guard let app = validated(target) else { message = "应用已退出、进程身份改变或受到保护，请刷新列表。"; refresh(); return }
        let accepted = force ? app.forceTerminate() : app.terminate()
        message = accepted ? (force ? "已向 \(target.name) 提交强制结束请求，列表会随采样更新。" : "已请求 \(target.name) 正常退出；如有保存提示，请先处理。") : "\(target.name) 未接受退出请求，请核对应用状态。"
    }
}

/// 使用现有 cleanMac 状态栏入口，不创建额外状态栏图标。
@MainActor
final class ResourceAlertPresenter: NSObject, NSPopoverDelegate {
    static let shared = ResourceAlertPresenter()
    weak var statusBarAnchor: NSView?
    private let popover = NSPopover()
    private var started = false
    private var presentationToken = 0
    private var pending = false
    private var retryWork: DispatchWorkItem?
    private let readyAfter = ProcessInfo.processInfo.systemUptime + 8
    func start() {
        guard !started else { return }; started = true
        popover.behavior = .transient; popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 480)
        popover.contentViewController = NSHostingController(rootView: HighResourcePopoverView())
        HighResourceMonitor.shared.onAlert = { [weak self] in self?.show() }
        HighResourceMonitor.shared.onUpdate = { [weak self] in self?.update() }
        HighResourceMonitor.shared.start()
    }
    private func update() {
        if !HighResourceMonitor.shared.enabled || HighResourceMonitor.shared.applications.isEmpty { close() }
    }
    func show() {
        guard HighResourceMonitor.shared.enabled, !HighResourceMonitor.shared.applications.isEmpty,
              !popover.isShown else { return }
        pending = true
        scheduleRetry()
    }
    private func scheduleRetry() {
        guard pending, retryWork == nil else { return }
        let token = presentationToken
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.presentationToken == token else { return }
            self.retryWork = nil
            self.presentWhenReady()
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
    private func presentWhenReady() {
        guard pending, HighResourceMonitor.shared.enabled, !HighResourceMonitor.shared.applications.isEmpty else { close(); return }
        guard ProcessInfo.processInfo.systemUptime >= readyAfter else { scheduleRetry(); return }
        if let anchor = resolvedStatusBarAnchor(), let window = anchor.window,
           window.frame.height > 0, window.screen != nil, !anchor.bounds.isEmpty {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
            if popover.isShown { pending = false; return }
        }
        // 启动时标签可能仍处于离屏布局阶段；只等待状态栏，不创建独立窗口。
        scheduleRetry()
    }
    private func resolvedStatusBarAnchor() -> NSView? {
        if let anchor = statusBarAnchor, let window = anchor.window,
           window.frame.height > 0, window.screen != nil, !anchor.bounds.isEmpty { return anchor }
        // SwiftUI 有时会在离屏窗口中渲染 MenuBarExtra 标签，改用当前应用真实的状态栏按钮。
        func buttons(in view: NSView) -> [NSStatusBarButton] {
            if let button = view as? NSStatusBarButton { return [button] }
            return view.subviews.flatMap { buttons(in: $0) }
        }
        let candidates = NSApp.windows.filter { $0.screen != nil && $0.frame.height > 0 }
            .flatMap { $0.contentView.map { buttons(in: $0) } ?? [] }
            .filter { !$0.bounds.isEmpty }
        if let button = candidates.first(where: { ["cleanMac", "有设备电量低，请充电"].contains($0.toolTip ?? "") }) { return button }
        if candidates.count == 1, candidates[0].toolTip?.hasPrefix("下载 ") != true { return candidates[0] }
        return nil
    }
    func close() {
        presentationToken += 1; pending = false
        retryWork?.cancel(); retryWork = nil
        popover.performClose(nil)
    }
    func popoverDidClose(_ notification: Notification) {
        presentationToken += 1; pending = false
        retryWork?.cancel(); retryWork = nil
    }

}


struct ResourceStatusBarAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { AnchorView() }
    func updateNSView(_ view: NSView, context: Context) {}
    final class AnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { ResourceAlertPresenter.shared.statusBarAnchor = self }
        }
    }
}
