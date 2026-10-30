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
    @Published private(set) var usageHistory: [String: [ApplicationUsagePoint]] = [:]
    @Published private(set) var ignoredBundleIDs = Set(UserDefaults.standard.stringArray(forKey: "com.cleanMac.resourceAlerts.ignoredApps") ?? [])
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
    private var policy = ResourceAlertPolicy(memoryThreshold: 4 * 1024 * 1024 * 1024)
    private var configuration = ""
    private var generation = 0
    private var alertReadyAfter = ProcessInfo.processInfo.systemUptime + 60
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
        let cpu = min(800, max(50, defaults.object(forKey: "com.cleanMac.resourceCPUThreshold") as? Double ?? 400))
        let memory = min(50, max(10, defaults.object(forKey: "com.cleanMac.resourceMemoryPercent") as? Double ?? 35))
        let samplingNeeded = enabled || !overviewClients.isEmpty
        let signature = "\(enabled):\(cpu):\(memory):\(samplingNeeded)"
        guard signature != configuration else { return }
        configuration = signature; generation += 1
        alertReadyAfter = ProcessInfo.processInfo.systemUptime + 60
        timer?.invalidate(); timer = nil; work?.cancel(); work = nil
        applications = []; allApplications = []; isSampling = false; previous = []; previousTime = 0
        policy = ResourceAlertPolicy(cpuThreshold: cpu, memoryThreshold: max(4 * 1024 * 1024 * 1024, UInt64(Double(ProcessInfo.processInfo.physicalMemory) * memory / 100)))
        onUpdate?()
        guard samplingNeeded else { return }
        refresh()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        timer.tolerance = 1; RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func retainOverview(_ id: UUID) { overviewClients.insert(id); start(); configure() }
    func releaseOverview(_ id: UUID) { overviewClients.remove(id); configure() }
    private func canAlert(_ app: ResourceAppDescriptor) -> Bool {
        !ignoredBundleIDs.contains(app.bundleID) && app.pid != ProcessInfo.processInfo.processIdentifier
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
        let eligibleIDs = Set(apps.filter { canAlert($0) && Date().timeIntervalSince($0.launchDate) >= 60 }.map(\.id))
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
            let liveIDs = Set(usage.map(\.id)), date = Date()
            usageHistory = usageHistory.filter { liveIDs.contains($0.key) }
            for entry in usage where entry.sampleAvailable {
                var values = (usageHistory[entry.id] ?? []).filter { date.timeIntervalSince($0.date) <= 300 }
                if let last = values.last, date.timeIntervalSince(last.date) > 12 { values = [] }
                values.append(.init(date: date, cpu: entry.cpuPercent, memory: entry.memory))
                usageHistory[entry.id] = Array(values.suffix(61))
            }
            allApplications = usage.sorted { $0.application.name.localizedStandardCompare($1.application.name) == .orderedAscending }
            // 提醒忽略或白名单可能在后台采样期间改变，提交结果前再核对一次。
            let result = policy.evaluate(usage.filter { $0.sampleAvailable && eligibleIDs.contains($0.id) && canAlert($0.application) }, now: now, notificationsEnabled: enabled && alertsAllowed && now >= alertReadyAfter)
            applications = enabled ? result.high : []
            if !apps.isEmpty && samples.isEmpty { message = "当前无法读取应用进程占用，请稍后重试。" }
            else if message == "当前无法读取应用进程占用，请稍后重试。" { message = nil }
            work = nil; isSampling = false
            onUpdate?()
            if !result.notify.isEmpty, snoozedUntil.map({ $0 <= Date() }) ?? true { onAlert?() }
        }
    }
    func setIgnored(_ app: ResourceAppDescriptor, ignored: Bool) {
        if ignored { ignoredBundleIDs.insert(app.bundleID) } else { ignoredBundleIDs.remove(app.bundleID) }
        UserDefaults.standard.set(ignoredBundleIDs.sorted(), forKey: "com.cleanMac.resourceAlerts.ignoredApps")
        if ignored { applications.removeAll { $0.application.bundleID == app.bundleID }; onUpdate?() }
        refresh()
    }
    func restoreAlert(bundleID: String) {
        ignoredBundleIDs.remove(bundleID)
        UserDefaults.standard.set(ignoredBundleIDs.sorted(), forKey: "com.cleanMac.resourceAlerts.ignoredApps")
        refresh()
    }
    func canEnd(_ app: ResourceAppDescriptor) -> Bool { validated(app) != nil }
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

/// 同一个原生状态项和弹窗承载仪表盘与异常提醒，避免两套弹窗互相唤起。
@MainActor
final class ResourceAlertPresenter: NSObject, NSPopoverDelegate {
    static let shared = ResourceAlertPresenter()
    private enum Content { case dashboard, alert }
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var content: Content?
    private var batterySubscription: AnyCancellable?
    private var started = false
    private var pending = false
    private var retryWork: DispatchWorkItem?
    private var retryUntil: TimeInterval = 0

    func start() {
        guard !started else { return }; started = true
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(toggleDashboard)
        renderIcon()
        batterySubscription = BatteryAlertMonitor.shared.objectWillChange
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.renderIcon() }
        popover.behavior = .transient; popover.delegate = self
        HighResourceMonitor.shared.onAlert = { [weak self] in self?.show() }
        HighResourceMonitor.shared.onUpdate = { [weak self] in self?.update() }
        HighResourceMonitor.shared.start()
    }

    private func renderIcon() {
        guard let button = statusItem?.button else { return }
        let warning = BatteryAlertMonitor.shared.hasBatteryWarning
        let image = NSImage(size: NSSize(width: warning ? 38 : 18, height: 18))
        image.lockFocus()
        NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: nil)?.draw(in: NSRect(x: 0, y: 1, width: 18, height: 16))
        if warning {
            let symbol = (BatteryAlertMonitor.shared.mostUrgentLevel ?? 100) <= 5 ? "battery.0percent" : "battery.25percent"
            NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.draw(in: NSRect(x: 21, y: 2, width: 17, height: 14))
        }
        image.unlockFocus(); image.isTemplate = true
        button.image = image
        button.toolTip = warning ? "有设备电量低，请充电" : "cleanMac"
        button.setAccessibilityLabel(warning ? "cleanMac，设备电量低，请充电" : "cleanMac")
    }

    @objc private func toggleDashboard() {
        // 自动提醒没有按钮点击或 MenuBarExtra 场景参与；只有用户点击才展示仪表盘。
        if popover.isShown { close(); return }
        cancelPending()
        present(.dashboard)
    }

    private func update() {
        if !HighResourceMonitor.shared.enabled || HighResourceMonitor.shared.applications.isEmpty {
            cancelPending()
            if content == .alert { close() }
        }
    }
    func show() {
        guard HighResourceMonitor.shared.enabled, !HighResourceMonitor.shared.applications.isEmpty,
              !popover.isShown else { return } // 不打断用户正在查看的普通仪表盘。
        cancelPending()
        pending = true; retryUntil = ProcessInfo.processInfo.systemUptime + 120
        presentWhenReady()
    }
    private func presentWhenReady() {
        retryWork = nil
        guard pending, HighResourceMonitor.shared.enabled, !HighResourceMonitor.shared.applications.isEmpty,
              !popover.isShown, ProcessInfo.processInfo.systemUptime < retryUntil else { cancelPending(); return }
        if present(.alert) { pending = false; return }
        let work = DispatchWorkItem { [weak self] in self?.presentWhenReady() }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
    @discardableResult private func present(_ next: Content) -> Bool {
        guard let button = statusItem?.button, let window = button.window,
              window.frame.height > 0, window.screen != nil, !button.bounds.isEmpty else { return false }
        switch next {
        case .dashboard:
            popover.contentSize = NSSize(width: 330, height: 570)
            popover.contentViewController = NSHostingController(rootView: MenuBarStatusView(onOpenMainWindow: {
                ResourceAlertPresenter.shared.close()
                AppActionCoordinator.shared.requestMainWindow()
            }))
        case .alert:
            popover.contentSize = NSSize(width: 420, height: 480)
            popover.contentViewController = NSHostingController(rootView: HighResourcePopoverView())
        }
        content = next
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(popover.isShown)
        return popover.isShown
    }
    private func cancelPending() {
        pending = false; retryWork?.cancel(); retryWork = nil
    }
    func close() {
        cancelPending(); popover.performClose(nil)
        content = nil; statusItem?.button?.highlight(false)
    }
    func popoverDidClose(_ notification: Notification) {
        cancelPending(); content = nil; statusItem?.button?.highlight(false)
    }
}
