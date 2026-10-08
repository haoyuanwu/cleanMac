import XCTest
@testable import cleanMac

/// 核心逻辑单元测试（在 Xcode 中添加测试 Target 后运行）
/// File → Add Target → Unit Testing Bundle → 将本文件加入该 Target
final class CoreLogicTests: XCTestCase {

    // MARK: - FileSizeFormatter
    func testFileSizeFormatterZero() {
        let s = FileSizeFormatter.string(fromByteCount: 0)
        XCTAssertFalse(s.isEmpty)
    }

    func testFileSizeFormatterGigabyte() {
        let s = FileSizeFormatter.string(fromByteCount: 1_500_000_000)
        XCTAssertTrue(s.contains("GB") || s.contains("G"))
    }

    // MARK: - 安全白名单
    func testBlockedSystemPaths() {
        XCTAssertTrue(SafetyWhitelist.isBlocked(path: "/System/Library/CoreServices/Finder.app"))
        XCTAssertTrue(SafetyWhitelist.isBlocked(path: "/usr/bin"))
        XCTAssertTrue(SafetyWhitelist.isBlocked(path: "/"))
    }

    func testUserCacheAllowed() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cache = home + "/Library/Caches/com.example.app"
        XCTAssertFalse(SafetyWhitelist.isBlocked(path: cache))
        XCTAssertTrue(SafetyWhitelist.canDelete(path: cache))
    }

    func testProtectedApps() {
        XCTAssertTrue(SafetyWhitelist.isProtectedApp(path: "/Applications/Safari.app"))
        XCTAssertTrue(SafetyWhitelist.isProtectedApp(path: "/System/Applications/System Settings.app"))
        XCTAssertFalse(SafetyWhitelist.isProtectedApp(path: "/Applications/WeChat.app"))
    }

    func testRiskLevels() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cacheRisk = SafetyWhitelist.riskLevel(for: home + "/Library/Caches/x", category: .systemCache)
        XCTAssertEqual(cacheRisk, .safe)

        let downloadRisk = SafetyWhitelist.riskLevel(for: home + "/Downloads/foo.dmg", category: .downloads)
        XCTAssertEqual(downloadRisk, .caution)

        let sysRisk = SafetyWhitelist.riskLevel(for: "/Library/Caches/Apple", category: .systemCache)
        XCTAssertEqual(sysRisk, .sensitive)
    }

    // MARK: - Dry-run
    func testDryRunBlocksRoot() {
        let d = DeleteDryRun.validate(path: "/")
        XCTAssertFalse(d.allowed)
    }

    func testDryRunAllowsUserDownload() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let d = DeleteDryRun.validate(path: home + "/Downloads/demo.zip")
        XCTAssertTrue(d.allowed)
    }

    func testDryRunBlocksOutsideSandbox() {
        let d = DeleteDryRun.validate(path: "/opt/secret")
        XCTAssertFalse(d.allowed)
    }

    // MARK: - 时间线
    func testAgeBucket() {
        XCTAssertEqual(FileAgeBucket.bucket(for: nil), .unknown)
        XCTAssertEqual(FileAgeBucket.bucket(for: Date()), .last30Days)
        let yearAgo = Calendar.current.date(byAdding: .year, value: -2, to: Date())
        XCTAssertEqual(FileAgeBucket.bucket(for: yearAgo), .older)
    }

    // MARK: - 智能清理
    func testSmartCleanOnlySafe() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let safe = FileItem(
            path: home + "/Library/Caches/safe.bin",
            name: "safe.bin",
            size: 1024,
            modificationDate: Date(),
            isDirectory: false
        )
        var safeAnnotated = safe
        safeAnnotated.riskLevel = .safe

        let caution = FileItem(
            path: home + "/Downloads/important.doc",
            name: "important.doc",
            size: 2048,
            modificationDate: Date(),
            isDirectory: false
        )
        var cautionAnnotated = caution
        cautionAnnotated.riskLevel = .caution

        let result = ScanResult(category: .systemCache, items: [safeAnnotated, cautionAnnotated])
        let plan = SmartCleanPlan.build(from: [.systemCache: result])

        XCTAssertEqual(plan.items.count, 1)
        XCTAssertEqual(plan.items.first?.path, safeAnnotated.path)
    }
}
