import XCTest
@testable import cleanMac

final class TrashMonitorTests: XCTestCase {
    private func runOnMain(_ body: @escaping @MainActor () async -> Void) {
        let finished = expectation(description: "monitor update")
        Task { @MainActor in await body(); finished.fulfill() }
        wait(for: [finished], timeout: 5)
    }

    @MainActor private static func outcome(_ bytes: Int64) -> TrashScanOutcome {
        .init(items: bytes == 0 ? [] : [.init(path: "/tmp/trash-monitor-fixture", name: "fixture", size: bytes,
                                             modificationDate: nil, isDirectory: false)], error: nil)
    }

    func testForcedRefreshBypassesRecentPopupSnapshot() {
        runOnMain {
            var bytes: Int64 = 10
            var scans = 0
            let monitor = TrashMonitor(scanTrash: { scans += 1; return Self.outcome(bytes) }, notificationsEnabled: false)
            await monitor.refresh()
            bytes = 25
            await monitor.refresh()
            XCTAssertEqual(scans, 1)
            XCTAssertEqual(monitor.status?.bytes, 10)
            await monitor.refresh(force: true)
            XCTAssertEqual(monitor.status?.bytes, 25)
            bytes = 0
            await monitor.refresh(force: true)
            XCTAssertEqual(monitor.status?.bytes, 0)
            XCTAssertEqual(monitor.status?.itemCount, 0)
        }
    }

    func testRefreshDuringScanRunsAgainInsteadOfLosingChange() {
        runOnMain {
            var continuation: CheckedContinuation<TrashScanOutcome, Never>?
            var scans = 0
            let monitor = TrashMonitor(scanTrash: {
                scans += 1
                if scans == 1 { return await withCheckedContinuation { continuation = $0 } }
                return Self.outcome(75)
            }, notificationsEnabled: false)
            let first = Task { await monitor.refresh(force: true) }
            while continuation == nil { await Task.yield() }
            await monitor.refresh(force: true)
            await monitor.refresh(force: true)
            continuation?.resume(returning: Self.outcome(10))
            await first.value
            XCTAssertEqual(scans, 2)
            XCTAssertEqual(monitor.status?.bytes, 75)
            XCTAssertFalse(monitor.isScanning)
        }
    }

    func testCleaningAndRestoreNotificationsUpdateRecentStatus() {
        runOnMain {
            let center = NotificationCenter()
            var bytes: Int64 = 15
            var scans = 0
            let monitor = TrashMonitor(scanTrash: { scans += 1; return Self.outcome(bytes) },
                                       notificationsEnabled: false, notificationCenter: center)
            monitor.start()
            while monitor.status == nil { try? await Task.sleep(for: .milliseconds(10)) }
            XCTAssertEqual(monitor.status?.bytes, 15)
            bytes = 30
            center.post(name: CleaningHistoryStore.didChange, object: nil)
            while scans < 2 { try? await Task.sleep(for: .milliseconds(10)) }
            XCTAssertEqual(monitor.status?.bytes, 30)
            bytes = 0
            center.post(name: .init("trashDidChange"), object: nil)
            while scans < 3 { try? await Task.sleep(for: .milliseconds(10)) }
            XCTAssertEqual(monitor.status?.itemCount, 0)
        }
    }
}
