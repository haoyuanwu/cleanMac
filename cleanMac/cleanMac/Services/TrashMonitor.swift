import Foundation
import Combine
import UserNotifications

enum TrashWarningLimit: Int, CaseIterable, Identifiable {
    case gb5 = 5
    case gb10 = 10
    case gb30 = 30
    case gb100 = 100
    case unlimited = 0

    var id: Int { rawValue }
    var title: String { self == .unlimited ? "不限" : "\(rawValue) GB" }
    var bytes: Int64? { self == .unlimited ? nil : Int64(rawValue) * 1_000_000_000 }
}

struct TrashStatus: Sendable {
    let bytes: Int64
    let itemCount: Int
    let error: String?
    let capturedAt: Date
}

@MainActor
final class TrashMonitor: ObservableObject {
    static let shared = TrashMonitor()

    @Published private(set) var limit: TrashWarningLimit
    @Published private(set) var status: TrashStatus?
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var actionMessage: String?

    private let limitKey = "com.cleanMac.trashWarning.limitGB"
    private let notifiedKey = "com.cleanMac.trashWarning.notified"
    private let notifiedLimitKey = "com.cleanMac.trashWarning.notifiedLimitGB"
    private let notificationID = "cleanMac.trashWarning"
    private let scanService = ScanService()
    private let cleanService = CleanService()
    private var timer: Timer?
    private var hasStarted = false
    private var notifiedAboveLimit: Bool
    private var isNotifying = false

    private init() {
        let defaults = UserDefaults.standard
        let selectedLimit = TrashWarningLimit(rawValue: defaults.object(forKey: limitKey) as? Int ?? 10) ?? .gb10
        limit = selectedLimit
        notifiedAboveLimit = defaults.bool(forKey: notifiedKey)
            && defaults.integer(forKey: notifiedLimitKey) == selectedLimit.rawValue
    }

    var percentage: Int? {
        guard let status, status.error == nil, let bytes = limit.bytes, bytes > 0 else { return nil }
        let ratio = Double(status.bytes) / Double(bytes)
        return ratio > 1 ? max(101, Int((ratio * 100).rounded())) : Int((ratio * 100).rounded())
    }

    var isOverLimit: Bool {
        guard let status, status.error == nil, let bytes = limit.bytes else { return false }
        return status.bytes > bytes
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        timer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh(force: true) }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        Task {
            await refresh(force: true)
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await notifyIfNeeded()
        }
    }

    func setLimit(_ newLimit: TrashWarningLimit) {
        guard limit != newLimit else { return }
        limit = newLimit
        UserDefaults.standard.set(newLimit.rawValue, forKey: limitKey)
        setNotified(false)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationID])
        Task { await refresh(force: true) }
    }

    func refresh(force: Bool = false) async {
        guard !isScanning, !isCleaning else { return }
        if !force, let status, Date().timeIntervalSince(status.capturedAt) < 5 * 60 { return }

        isScanning = true
        let result = await scanService.scanTrash()
        status = TrashStatus(
            bytes: result.items.reduce(0) { $0 + $1.size },
            itemCount: result.items.count,
            error: result.error,
            capturedAt: Date()
        )
        isScanning = false
        await notifyIfNeeded()
    }

    /// 菜单栏入口按用户选择直接清空，不依赖可能过期的上次扫描结果。
    func emptyTrash() async {
        guard !isCleaning, !isScanning else { return }
        isCleaning = true
        actionMessage = nil

        let latest = await scanService.scanTrash()
        if latest.error != nil {
            actionMessage = "无法读取部分废纸篓，请检查完全磁盘访问权限。"
        } else if latest.items.isEmpty {
            actionMessage = "废纸篓已是空的"
        } else {
            let outcome = await cleanService.emptyTrash(items: latest.items)
            actionMessage = outcome.failedCount == 0
                ? "已清理 \(FileSizeFormatter.string(fromByteCount: outcome.cleanedBytes))"
                : "已清理 \(FileSizeFormatter.string(fromByteCount: outcome.cleanedBytes))，\(outcome.failedCount) 项未能删除"
            NotificationCenter.default.post(name: .init("trashDidChange"), object: nil)
        }

        isCleaning = false
        await refresh(force: true)
    }

    private func notifyIfNeeded() async {
        guard let status, status.error == nil else { return }
        guard let threshold = limit.bytes else {
            setNotified(false)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationID])
            return
        }
        guard status.bytes > threshold else {
            setNotified(false)
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationID])
            return
        }
        guard !notifiedAboveLimit, !isNotifying else { return }
        let limitAtStart = limit
        let bytesAtStart = status.bytes
        isNotifying = true
        defer {
            isNotifying = false
            if (limit != limitAtStart || self.status?.bytes != bytesAtStart), isOverLimit, !notifiedAboveLimit {
                Task { await self.notifyIfNeeded() }
            }
        }

        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings().authorizationStatus
        guard authorization == .authorized || authorization == .provisional else { return }
        guard limit == limitAtStart, self.status?.bytes == bytesAtStart else { return }

        let content = UNMutableNotificationContent()
        content.title = "废纸篓已超过 \(limit.title) 警戒值"
        content.body = "当前占用 \(FileSizeFormatter.string(fromByteCount: status.bytes))（\(percentage ?? 0)%），请及时清理。"
        content.sound = .default
        content.categoryIdentifier = "CLEANMAC_TRASH_WARNING"

        do {
            try await center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: nil))
            if limit == limitAtStart, self.status?.bytes == bytesAtStart {
                setNotified(true)
            } else {
                center.removeDeliveredNotifications(withIdentifiers: [notificationID])
            }
        } catch {
            AppLog.warn("trash warning notification failed", metadata: ["error": error.localizedDescription])
        }
    }

    private func setNotified(_ notified: Bool) {
        notifiedAboveLimit = notified
        UserDefaults.standard.set(notified, forKey: notifiedKey)
        UserDefaults.standard.set(limit.rawValue, forKey: notifiedLimitKey)
    }
}
