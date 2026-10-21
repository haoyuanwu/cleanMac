import Foundation
import Combine
import UserNotifications

/// 在电量首次进入 20%、10%、5% 档位时提醒；恢复后允许下一次下降重新提醒。
@MainActor
final class BatteryAlertMonitor: ObservableObject {
    static let shared = BatteryAlertMonitor()
    nonisolated static let notificationCategory = "CLEANMAC_BATTERY_LOW"

    @Published private(set) var hasBatteryWarning = false
    @Published private(set) var mostUrgentLevel: Int?
    @Published private(set) var visibleChargeWarnings: [ChargeWarning] = []

    struct ChargeWarning: Identifiable {
        let id: String
        let name: String
        let level: Int
        let stage: Int
    }

    private var dismissedChargeStages: [String: Int] = [:]

    func dismissChargeWarnings() {
        for warning in visibleChargeWarnings {
            dismissedChargeStages[warning.id] = warning.stage
        }
        visibleChargeWarnings = []
    }

    private struct Reading {
        let macLevel: Int?
        let macOnBattery: Bool
        let bluetoothDevices: [BluetoothConnectedDevice]
    }

    private struct BatteryItem {
        let id: String
        let name: String
        let level: Int
        let shouldNotify: Bool
    }

    private let stagesKey = "com.cleanMac.batteryAlerts.notifiedStages"
    private var notifiedStages: [String: Int]
    private var timer: Timer?
    private var isEvaluating = false
    private var pendingReading: Reading?

    private init() {
        notifiedStages = UserDefaults.standard.dictionary(forKey: stagesKey) as? [String: Int] ?? [:]
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { await poll() }
    }

    func poll() async {
        let status = await Task.detached(priority: .utility) {
            DeviceInformationService.quickStatus()
        }.value
        await evaluate(status)
    }

    func evaluate(_ status: DeviceQuickStatus) async {
        await evaluate(Reading(
            macLevel: status.batteryLevel.map { Int(($0 * 100).rounded()) },
            macOnBattery: status.batteryState == "使用电池",
            bluetoothDevices: status.connectedBluetoothDevices
        ))
    }

    func evaluate(_ snapshot: DeviceInfoSnapshot) async {
        await evaluate(Reading(
            macLevel: snapshot.batteryLevel.map { Int(($0 * 100).rounded()) },
            macOnBattery: snapshot.battery.first(where: { $0.label == "状态" })?.value == "使用电池",
            bluetoothDevices: snapshot.connectedBluetoothDevices
        ))
    }

    private func evaluate(_ reading: Reading) async {
        let lowLevels = reading.bluetoothDevices.compactMap { $0.batteryLevel }.filter { $0 < 20 }
            + (reading.macOnBattery ? reading.macLevel.map { $0 < 20 ? [$0] : [] } ?? [] : [])
        mostUrgentLevel = lowLevels.min()
        hasBatteryWarning = !lowLevels.isEmpty

        var warnings = reading.bluetoothDevices.compactMap { device -> ChargeWarning? in
            guard let level = device.batteryLevel, level >= 0,
                  let stage = Self.stage(for: level) else { return nil }
            return ChargeWarning(id: "bluetooth.\(device.id)", name: device.name, level: level, stage: stage)
        }
        if reading.macOnBattery, let level = reading.macLevel, level >= 0,
           let stage = Self.stage(for: level) {
            warnings.append(ChargeWarning(id: "mac", name: "Mac", level: level, stage: stage))
        }
        // 恢复电量、接通电源或断开设备后清除关闭状态；进入更低档位时重新显示。
        dismissedChargeStages = dismissedChargeStages.filter { id, _ in
            warnings.contains { $0.id == id }
        }
        visibleChargeWarnings = warnings.filter { dismissedChargeStages[$0.id] != $0.stage }
            .sorted { $0.level == $1.level ? $0.id < $1.id : $0.level < $1.level }

        if isEvaluating {
            pendingReading = reading
            return
        }
        isEvaluating = true
        var current: Reading? = reading
        while let next = current {
            pendingReading = nil
            await process(next)
            current = pendingReading
        }
        isEvaluating = false
    }

    private func process(_ reading: Reading) async {
        var items: [BatteryItem] = reading.bluetoothDevices.compactMap { device in
            guard let level = device.batteryLevel, (0...100).contains(level) else { return nil }
            return BatteryItem(id: "bluetooth.\(device.id)", name: device.name, level: level, shouldNotify: true)
        }
        if let level = reading.macLevel, (0...100).contains(level) {
            items.append(BatteryItem(id: "mac", name: "Mac", level: level, shouldNotify: reading.macOnBattery))
        }

        var candidates: [(BatteryItem, Int)] = []
        var recoveredIDs: [String] = []
        var changed = false
        for item in items {
            guard let stage = Self.stage(for: item.level) else {
                if notifiedStages.removeValue(forKey: item.id) != nil {
                    recoveredIDs.append(item.id)
                    changed = true
                }
                continue
            }
            if let previous = notifiedStages[item.id], stage > previous {
                notifiedStages[item.id] = stage
                changed = true
            } else if item.shouldNotify,
                      notifiedStages[item.id].map({ stage < $0 }) ?? true {
                candidates.append((item, stage))
            }
        }

        let center = UNUserNotificationCenter.current()
        if !recoveredIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: recoveredIDs.flatMap { id in
                [20, 10, 5].map { Self.notificationID(for: id, stage: $0) }
            })
        }
        if changed { persist() }
        guard !candidates.isEmpty else { return }

        let authorization = await center.notificationSettings().authorizationStatus
        let permitted: Bool
        if authorization == .notDetermined {
            permitted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        } else {
            permitted = authorization == .authorized || authorization == .provisional
        }
        guard permitted else { return }

        for (item, stage) in candidates {
            let content = UNMutableNotificationContent()
            content.title = item.id == "mac"
                ? "电脑电量低：\(item.level)%"
                : "\(item.name) 电量低：\(item.level)%"
            switch stage {
            case 5: content.body = "电量已降至 5% 或更低，请尽快充电。"
            case 10: content.body = "电量已降至 10% 或更低，请及时充电。"
            default: content.body = "电量已低于 20%，请及时充电。"
            }
            content.sound = .default
            content.categoryIdentifier = Self.notificationCategory

            do {
                try await center.add(UNNotificationRequest(
                    identifier: Self.notificationID(for: item.id, stage: stage),
                    content: content,
                    trigger: nil
                ))
                notifiedStages[item.id] = stage
                persist()
            } catch {
                AppLog.warn("battery notification failed", metadata: ["error": error.localizedDescription])
            }
        }
    }

    private static func stage(for level: Int) -> Int? {
        if level <= 5 { return 5 }
        if level <= 10 { return 10 }
        if level < 20 { return 20 }
        return nil
    }

    private static func notificationID(for id: String, stage: Int) -> String {
        "cleanMac.battery.\(id).\(stage)"
    }

    private func persist() {
        UserDefaults.standard.set(notifiedStages, forKey: stagesKey)
    }
}
