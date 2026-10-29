import XCTest
@testable import cleanMac

final class StorageAccountingTests: XCTestCase {
    private func item(_ path: String, directory: Bool = false, size: Int64 = 10) -> FileItem {
        FileItem(path: path, name: (path as NSString).lastPathComponent, size: size, modificationDate: nil, isDirectory: directory)
    }

    func testExactPathsHaveStableCategoryOwnership() {
        let file = item("/fixture/cache")
        for groups in [[(.systemCache, [file]), (.applicationCache, [file]), (.browserCache, [file])],
                       [(.browserCache, [file]), (.applicationCache, [file]), (.systemCache, [file])]] as [[(ScanCategory, [FileItem])]] {
            let owned = ScanPathOwnership.unique(groups)
            XCTAssertEqual(owned.count, 1)
            XCTAssertEqual(owned.first?.0, .browserCache)
        }
    }

    func testParentChildDedupKeepsSiblingWithCommonPrefix() {
        let owned = ScanPathOwnership.unique([(.systemCache, [item("/fixture/cache", directory: true, size: 100)]),
                                             (.applicationCache, [item("/fixture/cache/child"), item("/fixture/cache-other")])])
        XCTAssertEqual(Set(owned.map { $0.1.path }), ["/fixture/cache", "/fixture/cache-other"])
        XCTAssertEqual(owned.reduce(0) { $0 + $1.1.size }, 110)
    }

    func testReconciliationCanRestoreChildWhenParentIsRescannedAway() {
        var results: [ScanCategory: ScanResult] = [
            .systemCache: ScanResult(category: .systemCache, items: [item("/fixture/cache", directory: true)]),
            .applicationCache: ScanResult(category: .applicationCache, items: [item("/fixture/cache/child")])
        ]
        ScanPathOwnership.reconcile(&results)
        XCTAssertEqual(results[.applicationCache]?.items.count, 0)
        XCTAssertEqual(results[.applicationCache]?.overlappingItems.count, 1)
        results[.systemCache] = ScanResult(category: .systemCache, items: [])
        ScanPathOwnership.reconcile(&results)
        XCTAssertEqual(results[.applicationCache]?.items.count, 1)
    }

    func testSmartCleanExcludesCloudPlaceholdersCancelledResultsAndPermanentTrash() {
        let cloud = FileItem(path: "/Users/test/Library/Caches/cloud", name: "cloud", size: 100,
                             modificationDate: nil, isDirectory: false,
                             storage: .init(logicalBytes: 100, allocatedBytes: 0, cloudPlaceholderCount: 1))
        let safe = item("/Users/test/Library/Caches/local")
        let collector = ScanDiagnosticsCollector()
        let results: [ScanCategory: ScanResult] = [
            .applicationCache: ScanResult(category: .applicationCache, items: [cloud]),
            .systemCache: ScanResult(category: .systemCache, items: [safe], diagnostics: collector.snapshot(finished: true, cancelled: true)),
            .trash: ScanResult(category: .trash, items: [item("/Users/test/.Trash/file")])
        ]
        XCTAssertTrue(SmartCleanPlan.build(from: results).isEmpty)
        XCTAssertFalse(SmartCleanPlan.build(from: [.applicationCache: ScanResult(category: .applicationCache, items: [safe])]).isEmpty)
    }

    func testSparseFileReportsLogicalAndAllocatedSizeSeparately() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sparse")
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data()))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 8 * 1024 * 1024)
        try handle.close()
        let collector = ScanDiagnosticsCollector()
        ScanContext.$diagnostics.withValue(collector) {
            let size = FileHelper.directorySize(root.path)
            let measurement = collector.measurement(for: root.path)
            XCTAssertEqual(size, 8 * 1024 * 1024)
            XCTAssertNotNil(measurement?.allocatedBytes)
            XCTAssertLessThan(measurement?.allocatedBytes ?? Int64.max, size)
            XCTAssertEqual(measurement?.cloudPlaceholderCount, 0)
        }
    }
}
