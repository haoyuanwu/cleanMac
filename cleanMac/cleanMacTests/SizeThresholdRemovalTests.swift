import XCTest
@testable import cleanMac

final class SizeThresholdRemovalTests: XCTestCase {
    private var home: URL!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }
    @discardableResult private func write(_ relative: String, bytes: Data = Data()) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        return url
    }

    func testSizeSortedInventoryIncludesSmallEmptyAndMoreThan100Files() async throws {
        for index in 0..<105 { try write("Documents/photo-\(index).png", bytes: Data([1])) }
        try write("Downloads/empty.txt")
        let items = await ScanService(homeDirectory: home).scanLargeFiles()
        XCTAssertEqual(items.filter { !$0.isDirectory }.count, 106)
        XCTAssertTrue(items.contains { $0.name == "empty.txt" && $0.size == 0 })
        XCTAssertTrue(items.contains { $0.name == "photo-104.png" && $0.size == 1 })
    }

    func testDuplicateScanFindsSmallAndEmptyDuplicates() async throws {
        try write("Downloads/a.png", bytes: Data([1, 2]))
        try write("Downloads/b.png", bytes: Data([1, 2]))
        try write("Downloads/empty-one.txt")
        try write("Downloads/empty-two.txt")
        let groups = await DuplicateFileScanner.findDuplicates(roots: [home.appendingPathComponent("Downloads").path])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.size)), [0, 2])
        XCTAssertTrue(groups.allSatisfy { $0.files.count == 2 })
    }

    func testApplicationCacheIncludesEmptyCacheFileAndFolder() throws {
        let empty = try write("Data/empty.cache")
        let cache = home.appendingPathComponent("Data/Cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let owner = CacheApplication(id: "com.example.SizeTest", name: "Size Test", path: nil)
        let roots = [ApplicationCacheScanner.DataRoot(url: home.appendingPathComponent("Data"), owner: owner, isCacheRoot: false)]
        let items = ApplicationCacheScanner.cacheItems(in: roots)
        XCTAssertTrue(items.contains { $0.path == empty.path && $0.size == 0 })
        XCTAssertTrue(items.contains { $0.path == cache.path && $0.size == 0 && $0.isDirectory })
    }

    func testXcodeInventoryIncludesEmptyArtifact() async throws {
        let empty = try write("Library/Developer/Xcode/DerivedData/empty.log")
        let result = await XcodeAnalysisService(homeDirectory: home).analyze()
        XCTAssertTrue(result.artifacts.contains { $0.path == empty.path && $0.size == 0 })
    }
}
