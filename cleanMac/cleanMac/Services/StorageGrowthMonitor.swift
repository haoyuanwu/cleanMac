import Foundation
import Combine
import UserNotifications

struct StorageGrowthSample: Codable, Sendable {
    let timestamp: Date
    let totalBytes: Int64
    let usedBytes: Int64
}

struct StorageGrowthChange: Identifiable {
    let timestamp: Date
    let deltaBytes: Int64
    var id: Date { timestamp }
}

private struct StorageGrowthHistory: Codable {
    var baselineUsedBytes: Int64?
    var baselineTotalBytes: Int64?
    var samples: [StorageGrowthSample] = []
}

/// 定时读取启动卷容量。只比较卷的已用空间，不遍历用户文件。
@MainActor
final class StorageGrowthMonitor: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = StorageGrowthMonitor()
    static let interval: TimeInterval = 30 * 60
    static let thresholdBytes: Int64 = 5_000_000_000

    @Published private(set) var isEnabled: Bool
    @Published private(set) var lastSample: StorageGrowthSample?
    @Published private(set) var growthBytes: Int64 = 0

    var recentChanges: [StorageGrowthChange] {
        let samples = Array(history.samples.suffix(6))
        guard samples.count > 1 else { return [] }
        let changes = zip(samples.dropFirst(), samples).map { pair in
            StorageGrowthChange(timestamp: pair.0.timestamp, deltaBytes: pair.0.usedBytes - pair.1.usedBytes)
        }
        return Array(changes.reversed())
    }

    private let enabledKey = "com.cleanMac.storageGrowth.enabled"
    private let historyKey = "com.cleanMac.storageGrowth.history"
    private let cleanActionID = "CLEANMAC_STORAGE_GROWTH_CLEAN"
    private let categoryID = "CLEANMAC_STORAGE_GROWTH"
    private var history: StorageGrowthHistory
    private var timer: Timer?
    private var isSampling = false
    private var hasStarted = false

    private override init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        history = defaults.data(forKey: historyKey)
            .flatMap { try? JSONDecoder().decode(StorageGrowthHistory.self, from: $0) }
            ?? StorageGrowthHistory()
        lastSample = history.samples.last
        super.init()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let cleanAction = UNNotificationAction(identifier: cleanActionID, title: "清理扫描", options: [.foreground])
        let laterAction = UNNotificationAction(identifier: "CLEANMAC_STORAGE_GROWTH_LATER", title: "稍后", options: [])
        let reviewTrashAction = UNNotificationAction(identifier: "CLEANMAC_TRASH_REVIEW", title: "查看废纸篓", options: [.foreground])
        let trashLaterAction = UNNotificationAction(identifier: "CLEANMAC_TRASH_LATER", title: "稍后", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: categoryID, actions: [cleanAction, laterAction], intentIdentifiers: []),
            UNNotificationCategory(identifier: "CLEANMAC_TRASH_WARNING", actions: [reviewTrashAction, trashLaterAction], intentIdentifiers: [])
        ])

        timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.recordSample() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }

        guard isEnabled else { return }
        Task {
            await recordSample()
            if await requestNotificationPermission(), growthBytes > Self.thresholdBytes {
                await recordSample()
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled {
            Task {
                await recordSample()
                if await requestNotificationPermission(), growthBytes > Self.thresholdBytes {
                    await recordSample()
                }
            }
        }
    }

    private func requestNotificationPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func recordSample() async {
        guard isEnabled, !isSampling else { return }
        isSampling = true
        defer { isSampling = false }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: home),
              let total = attributes[.systemSize] as? Int64,
              let free = attributes[.systemFreeSize] as? Int64,
              total > 0, (0...total).contains(free) else { return }

        let sample = StorageGrowthSample(timestamp: Date(), totalBytes: total, usedBytes: total - free)
        StorageTimeline.record(
            timestamp: sample.timestamp,
            totalBytes: total,
            usedBytes: sample.usedBytes,
            freeBytes: free
        )
        lastSample = sample
        history.samples.append(sample)
        if history.samples.count > 336 { history.samples.removeFirst(history.samples.count - 336) }

        if history.baselineTotalBytes != total || history.baselineUsedBytes == nil {
            history.baselineTotalBytes = total
            history.baselineUsedBytes = sample.usedBytes
        }
        if let baseline = history.baselineUsedBytes, sample.usedBytes < baseline {
            history.baselineUsedBytes = sample.usedBytes
        }

        let increase = max(0, sample.usedBytes - (history.baselineUsedBytes ?? sample.usedBytes))
        growthBytes = increase
        if increase > Self.thresholdBytes, await sendGrowthNotification(bytes: increase) {
            history.baselineUsedBytes = sample.usedBytes
            growthBytes = 0
        }
        persistHistory()
    }

    private func sendGrowthNotification(bytes: Int64) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return false }

        let amount = FileSizeFormatter.string(fromByteCount: bytes)
        let content = UNMutableNotificationContent()
        content.title = "磁盘已用空间增长了 \(amount)"
        content.body = "检测到新增的磁盘占用。要打开 cleanMac 扫描可清理内容吗？"
        content.sound = .default
        content.categoryIdentifier = categoryID

        do {
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            AppLog.info("storage growth notification", metadata: ["bytes": "\(bytes)"])
            return true
        } catch {
            AppLog.warn("storage growth notification failed", metadata: ["error": error.localizedDescription])
            return false
        }
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let isTrashWarning = category == "CLEANMAC_TRASH_WARNING"
        completionHandler()
        guard (category == "CLEANMAC_STORAGE_GROWTH" && action != "CLEANMAC_STORAGE_GROWTH_LATER")
                || (isTrashWarning && action != "CLEANMAC_TRASH_LATER") else { return }
        Task { @MainActor in
            if action == "CLEANMAC_STORAGE_GROWTH_CLEAN" {
                AppActionCoordinator.shared.requestOverviewScan()
            } else if isTrashWarning {
                AppActionCoordinator.shared.requestTrashReview()
            }
            AppActionCoordinator.shared.requestMainWindow()
        }
    }
}
