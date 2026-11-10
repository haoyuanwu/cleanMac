import XCTest
import Security
@testable import cleanMac

final class AppActionCoordinatorTests: XCTestCase {
    func testDetailRequestsAreRetainedUntilConsumedAndDeliveredOnlyOnce() async {
        await MainActor.run {
            let coordinator = AppActionCoordinator.shared
            _ = coordinator.consumeDeviceDetailRequest()
            for page in AppActionCoordinator.DeviceDetailPage.allCases {
                let revision = coordinator.deviceDetailRequest
                coordinator.requestDeviceDetail(page)
                XCTAssertEqual(coordinator.deviceDetailRequest, revision + 1)
                XCTAssertEqual(coordinator.consumeDeviceDetailRequest(), page)
                XCTAssertNil(coordinator.consumeDeviceDetailRequest())
            }
        }
    }
    func testLatestDetailRequestReplacesStaleNavigation() async {
        await MainActor.run {
            let coordinator = AppActionCoordinator.shared
            coordinator.requestDeviceInfo()
            coordinator.requestTrashReview()
            coordinator.requestDeviceDetail(.memory)
            coordinator.requestDeviceDetail(.connections)
            XCTAssertEqual(coordinator.consumeDeviceDetailRequest(), .connections)
            XCTAssertFalse(coordinator.consumeDeviceInfoRequest())
            XCTAssertFalse(coordinator.consumeTrashReviewRequest())
            XCTAssertNil(coordinator.consumeDeviceDetailRequest())
        }
    }
    func testMemoryMaintenanceStartsDirectlyAndCannotStartTwiceWhileRunning() async {
        let calls = MemoryOperationCallCount()
        let service = await MainActor.run { MemoryMaintenanceService(operation: {
            calls.record()
            return "已取消管理员授权，未执行内存整理。"
        }) }
        let state = await MainActor.run { () -> Bool in
            service.run()
            service.run()
            return service.running
        }
        XCTAssertTrue(state)
        for _ in 0..<200 {
            if await MainActor.run(body: { !service.running }) { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let message = await MainActor.run { service.message }
        XCTAssertEqual(message, "已取消管理员授权，未执行内存整理。")
        XCTAssertEqual(calls.value, 1)
    }
    func testHelperSignatureRequirementParsesAndRejectsUnsignedCode() throws {
        let text = MemoryHelperIdentity.requirement(identifier: MemoryHelperIdentity.client, team: "XSHY85VP6T")
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess)
        XCTAssertNotNil(requirement)
        XCTAssertNil(MemoryHelperIdentity.signature(at: URL(fileURLWithPath: "/bin/sh")), "Apple system code has no matching application team")
    }

    func testMemoryMaintenanceCompletionDoesNotPromiseReleasedBytes() async {
        let service = await MainActor.run { MemoryMaintenanceService(operation: { nil }) }
        await MainActor.run { service.run() }
        for _ in 0..<200 {
            if await MainActor.run(body: { !service.running }) { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let message = await MainActor.run { service.message ?? "" }
        XCTAssertTrue(message.hasPrefix("系统缓存整理完成。"))
        XCTAssertTrue(message.contains("不释放应用正在使用的内存"))
        XCTAssertTrue(message.contains("内存数值可能不变"))
    }

}

private final class MemoryOperationCallCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func record() { lock.lock(); defer { lock.unlock() }; count += 1 }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
