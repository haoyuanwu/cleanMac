import Foundation
import Combine
import IOKit.ps

/// 设备页、状态栏与电量提醒共用同一份后台快照；仅保留最新状态。
@MainActor
final class DeviceStatusMonitor: ObservableObject {
    static let shared = DeviceStatusMonitor()
    static let interval: TimeInterval = 5

    @Published private(set) var snapshot: DeviceInfoSnapshot?
    @Published private(set) var isRefreshing = false
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var powerSourceNotification: CFRunLoopSource?
    private var refreshAgain = false

    private init() {}

    func start() {
        guard timer == nil else { return }
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            Task { @MainActor in await DeviceStatusMonitor.shared.refresh(afterPowerChange: true) }
        }, nil)?.takeRetainedValue() {
            powerSourceNotification = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await refresh() }
    }

    /// 普通刷新共用正在进行的任务；电源事件在读取结束后补采，避免发布过时状态。
    func refresh(afterPowerChange: Bool = false) async {
        if let refreshTask {
            if afterPowerChange { refreshAgain = true }
            await refreshTask.value
            return
        }
        isRefreshing = true
        let task = Task {
            repeat {
                refreshAgain = false
                let previous = snapshot
                let next = await Task.detached(priority: .utility) {
                    DeviceInformationService.load(previous: previous)
                }.value
                if refreshAgain { continue }
                snapshot = next
            } while refreshAgain
        }
        refreshTask = task
        await task.value
        refreshTask = nil
        isRefreshing = false
    }
}
