import AppKit
import Combine

/// 在应用运行期间按本地时间执行每日概览扫描，不自动删除文件。
@MainActor
final class ScheduledScanService: ObservableObject {
    static let shared = ScheduledScanService()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var hour: Int
    @Published private(set) var minute: Int
    @Published private(set) var nextRun: Date?
    @Published private(set) var lastCompletedAt: Date?

    private let enabledKey = "com.cleanMac.scheduledScan.enabled"
    private let hourKey = "com.cleanMac.scheduledScan.hour"
    private let minuteKey = "com.cleanMac.scheduledScan.minute"
    private let lastStartedKey = "com.cleanMac.scheduledScan.lastStarted"
    private let lastCompletedKey = "com.cleanMac.scheduledScan.lastCompleted"

    private var timer: Timer?
    private var retryTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var clockObserver: NSObjectProtocol?
    private var timeZoneObserver: NSObjectProtocol?
    private var pendingScanDay: Date?
    private var lastStartedAt: Date?
    private var hasStarted = false

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        hour = (0...23).contains(defaults.integer(forKey: hourKey)) ? defaults.integer(forKey: hourKey) : 12
        minute = (0...59).contains(defaults.integer(forKey: minuteKey)) ? defaults.integer(forKey: minuteKey) : 0
        if defaults.object(forKey: hourKey) == nil { hour = 12 }
        lastStartedAt = defaults.object(forKey: lastStartedKey) as? Date
        lastCompletedAt = defaults.object(forKey: lastCompletedKey) as? Date
    }

    var selectedTime: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
        clockObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
        timeZoneObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleNext() }
        }
        scheduleNext()
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        pendingScanDay = nil
        retryTimer?.invalidate()
        retryTimer = nil
        scheduleNext()
    }

    func setTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let newHour = components.hour, let newMinute = components.minute,
              hour != newHour || minute != newMinute else { return }
        hour = newHour
        minute = newMinute
        UserDefaults.standard.set(newHour, forKey: hourKey)
        UserDefaults.standard.set(newMinute, forKey: minuteKey)
        pendingScanDay = nil
        retryTimer?.invalidate()
        retryTimer = nil
        scheduleNext()
    }

    private func scheduleNext() {
        timer?.invalidate()
        timer = nil
        nextRun = nil
        guard isEnabled, hasStarted else { return }

        let calendar = Calendar.current
        let now = Date()
        guard let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return }
        let alreadyScannedToday = lastStartedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        guard let next = today > now && !alreadyScannedToday
            ? today
            : calendar.date(byAdding: .day, value: 1, to: today) else { return }
        nextRun = next
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.scheduledTimeReached() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func handleWake() {
        guard isEnabled else { return }
        if let nextRun, nextRun <= Date() {
            scheduledTimeReached()
        } else {
            scheduleNext()
        }
    }

    private func scheduledTimeReached() {
        guard isEnabled else { return }
        retryTimer?.invalidate()
        retryTimer = nil
        pendingScanDay = Date()
        scheduleNext()
        attemptPendingScan()
    }

    private func attemptPendingScan() {
        guard isEnabled, let pendingScanDay else { return }
        let now = Date()
        guard Calendar.current.isDate(pendingScanDay, inSameDayAs: now) else {
            self.pendingScanDay = nil
            return
        }
        if let lastStartedAt, Calendar.current.isDate(lastStartedAt, inSameDayAs: now) {
            self.pendingScanDay = nil
            return
        }

        let viewModel = MainViewModel.shared
        guard !viewModel.isScanning, !viewModel.isCleaning else {
            retryTimer?.invalidate()
            let retryTimer = Timer(timeInterval: 5 * 60, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.attemptPendingScan() }
            }
            RunLoop.main.add(retryTimer, forMode: .common)
            self.retryTimer = retryTimer
            return
        }

        self.pendingScanDay = nil
        lastStartedAt = now
        UserDefaults.standard.set(now, forKey: lastStartedKey)
        AppLog.info("Scheduled overview scan started")
        Task {
            await viewModel.scanAll(showDonationAfterCompletion: false)
            if viewModel.overallProgress >= 1 {
                let completedAt = Date()
                lastCompletedAt = completedAt
                UserDefaults.standard.set(completedAt, forKey: lastCompletedKey)
                AppLog.info("Scheduled overview scan finished")
            } else {
                AppLog.warn("Scheduled overview scan interrupted")
            }
        }
    }
}
