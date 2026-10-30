import Foundation
import Combine

@MainActor final class BatteryHistoryMonitor: ObservableObject {
    static let shared = BatteryHistoryMonitor()
    @Published private(set) var history: [BatteryHistoryPoint] = []
    private let key = "com.cleanMac.batteryHistory.v1"
    private var lastPersisted = Date.distantPast
    private init() {
        if let data = UserDefaults.standard.data(forKey: key), let values = try? JSONDecoder().decode([BatteryHistoryPoint].self, from: data) {
            history = BatteryHistoryPolicy.retained(values, now: Date())
        }
    }
    func record(_ snapshot: DeviceInfoSnapshot) {
        guard let level = snapshot.batteryLevel, level.isFinite, (0...1).contains(level) else { return }
        let now = snapshot.capturedAt
        let state = snapshot.battery.first { $0.label == "状态" }?.value ?? "未知"
        if let last = history.last, state == last.state, now.timeIntervalSince(last.date) < 60 { return }
        history = BatteryHistoryPolicy.retained(history + [BatteryHistoryPoint(date: now, level: level, state: state)], now: now)
        if now.timeIntervalSince(lastPersisted) >= 60 || history.dropLast().last?.state != state {
            UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: key); lastPersisted = now
        }
    }
}
