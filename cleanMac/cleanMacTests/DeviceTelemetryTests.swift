import Foundation
import XCTest
@testable import cleanMac

final class DeviceTelemetryTests: XCTestCase {
    func testCPUDeltaUsesUserNiceSystemIdleAndNormalizesAllCores() {
        let value = CPUUsage.between(.init(user: 10, system: 10, idle: 10, nice: 10), .init(user: 30, system: 30, idle: 60, nice: 20))
        XCTAssertEqual(value?.user ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(value?.system ?? -1, 20, accuracy: 0.001)
        XCTAssertEqual(value?.idle ?? -1, 50, accuracy: 0.001)
        XCTAssertEqual(value?.used ?? -1, 50, accuracy: 0.001)
    }
    func testCPUZeroTicksHaveNoInventedReading() {
        let tick = CPUTicks(user: 1, system: 2, idle: 3, nice: 4)
        XCTAssertNil(CPUUsage.between(tick, tick))
    }
    func testCPUCounterWrapKeepsCorrectDelta() {
        let reading = CPUUsage.between(.init(user: UInt32.max - 4, system: 0, idle: 0, nice: 0), .init(user: 5, system: 0, idle: 10, nice: 0))
        XCTAssertEqual(reading?.used ?? -1, 50, accuracy: 0.001)
    }
    func testDiskRateMatchesDeviceIdentityAndExcludesNewlyAttachedDevices() {
        let value = DiskTransferRate.between([1: .init(read: 100, written: 100)], [1: .init(read: 300, written: 500), 2: .init(read: 90000, written: 90000)], seconds: 2)
        XCTAssertEqual(value?.read, 100); XCTAssertEqual(value?.written, 200)
    }
    func testDiskRateRejectsResetAndSleepGap() {
        XCTAssertNil(DiskTransferRate.between([1: .init(read: 500, written: 100)], [1: .init(read: 10, written: 500)], seconds: 2))
        XCTAssertNil(DiskTransferRate.between([1: .init(read: 1, written: 1)], [1: .init(read: 900, written: 900)], seconds: 60))
        XCTAssertNil(DiskTransferRate.between([:], [:], seconds: 0))
    }
    func testBatteryRetentionRejectsFutureInvalidAndExpiredValues() {
        let now = Date(timeIntervalSince1970: 200000)
        let values = [BatteryHistoryPoint(date: now, level: 0.5, state: "使用电池"), .init(date: now.addingTimeInterval(1), level: 0.5, state: "使用电池"), .init(date: now.addingTimeInterval(-90000), level: 0.5, state: "使用电池"), .init(date: now.addingTimeInterval(-1), level: .nan, state: "使用电池"), .init(date: now.addingTimeInterval(-2), level: 1.1, state: "使用电池")]
        XCTAssertEqual(BatteryHistoryPolicy.retained(values, now: now).count, 1)
    }
    func testBatteryRetentionSortsAndDeduplicates() {
        let now = Date()
        let point = BatteryHistoryPoint(date: now, level: 0.6, state: "使用电池")
        let values = [point, .init(date: now.addingTimeInterval(-60), level: 0.7, state: "使用电池"), point]
        let result = BatteryHistoryPolicy.retained(values, now: now)
        XCTAssertEqual(result.count, 2); XCTAssertLessThan(result[0].date, result[1].date)
    }
    func testBatteryRateNeedsFiveMinutesOfContinuousSameState() {
        let date = Date()
        let values = (0...5).map { BatteryHistoryPoint(date: date.addingTimeInterval(Double($0) * 60), level: 0.8 - Double($0) * 0.01, state: "使用电池") }
        XCTAssertNil(BatteryHistoryPolicy.hourlyChange(Array(values.prefix(5))))
        XCTAssertEqual(BatteryHistoryPolicy.hourlyChange(values) ?? 0, -60, accuracy: 0.001)
        var changed = values; changed.append(.init(date: date.addingTimeInterval(360), level: 0.75, state: "正在充电"))
        XCTAssertNil(BatteryHistoryPolicy.hourlyChange(changed))
    }
    func testBatteryRateAndCurveDoNotBridgeSleepGap() {
        let date = Date()
        let values = [BatteryHistoryPoint(date: date, level: 0.8, state: "使用电池"), .init(date: date.addingTimeInterval(600), level: 0.6, state: "使用电池")]
        XCTAssertNil(BatteryHistoryPolicy.hourlyChange(values))
        XCTAssertEqual(BatteryHistoryPolicy.segmentIDs(values), [0, 1])
    }
    func testBatteryEventsOnlyRecordObservedTransitions() {
        let date = Date()
        let values = [BatteryHistoryPoint(date: date, level: 0.8, state: "使用电池"), .init(date: date.addingTimeInterval(60), level: 0.8, state: "正在充电"), .init(date: date.addingTimeInterval(600), level: 1, state: "已充满")]
        XCTAssertEqual(BatteryHistoryPolicy.events(values).map(\.state), ["正在充电"])
    }
    func testReportExcludesIdentifiersAndUserPaths() {
        let text = DeviceReportRedactor.render(sections: [("硬件", [("芯片", "Apple M5"), ("序列号", "SECRET"), ("设备名称", "PRIVATE"), ("SSID", "HOME"), ("其他", "/Users/test/file")])], date: Date())
        XCTAssertTrue(text.contains("Apple M5")); XCTAssertFalse(text.contains("SECRET")); XCTAssertFalse(text.contains("PRIVATE")); XCTAssertFalse(text.contains("HOME")); XCTAssertFalse(text.contains("/Users/test"))
    }
    func testApplicationAggregationExposesEachAssociatedProcessWithStableIdentity() {
        let app = ResourceAppDescriptor(pid: 90, launchDate: Date(), bundleID: "example", name: "Example", path: "/Applications/Example.app")
        let old = ResourceProcessSample(pid: 90, parent: 1, birth: 4, path: app.path + "/app", cpuNanoseconds: 1_000_000_000, memory: 200)
        let next = ResourceProcessSample(pid: 90, parent: 1, birth: 4, path: old.path, cpuNanoseconds: 3_000_000_000, memory: 300)
        let result = ApplicationResourceReader.aggregate(applications: [app], current: [next], previous: [old], elapsed: 2)
        XCTAssertEqual(result[0].processes[0].id, "90:4"); XCTAssertEqual(result[0].processes[0].cpuPercent, 100); XCTAssertEqual(result[0].processes[0].memory, 300)
    }
}
