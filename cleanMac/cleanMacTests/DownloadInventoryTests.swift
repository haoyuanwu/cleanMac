import XCTest
@testable import cleanMac

final class DownloadInventoryTests: XCTestCase {
    func testApplicationInventoryReusesUnchangedItemsAndRefreshesChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = root.appendingPathComponent("Example.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let payload = contents.appendingPathComponent("payload")
        try Data([1]).write(to: payload)
        let service = ScanService(homeDirectory: root)
        let first = await service.scanApplications(searchPaths: [root.path])
        let second = await service.scanApplications(searchPaths: [root.path])
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.first?.size, 1)
        if CacheEventMonitor.shared.token(for: app.path).available {
            XCTAssertEqual(first.first?.id, second.first?.id)
        }
        try Data([1, 2, 3, 4]).write(to: payload)
        CacheEventMonitor.shared.record(paths: [payload.path], eventLoss: false)
        let updated = await service.scanApplications(searchPaths: [root.path])
        XCTAssertEqual(updated.first?.size, 4)
        XCTAssertNotEqual(first.first?.id, updated.first?.id)
        CacheEventMonitor.shared.invalidateAll()
        let invalidated = await service.scanApplications(searchPaths: [root.path])
        XCTAssertNotEqual(updated.first?.id, invalidated.first?.id)
        try FileManager.default.removeItem(at: app)
        let replacement = root.appendingPathComponent("New.app")
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        let final = await service.scanApplications(searchPaths: [root.path])
        XCTAssertEqual(final.map(\.path), [replacement.path])
    }

    func testDownloadsIncludeEveryFileTypeRegardlessOfSize() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloads = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let names = ["photo.jpg", "screenshot.png", "picture.heic", "vector.svg", "document.pdf",
                     "note.txt", "audio.mp3", "movie.mp4", "archive.zip", "installer.dmg", "unknown.custom", "README"]
        for name in names { try Data([1, 2, 3]).write(to: downloads.appendingPathComponent(name)) }
        try Data().write(to: downloads.appendingPathComponent("empty.txt"))
        let items = await ScanService(homeDirectory: home).scanDownloads()
        XCTAssertEqual(Set(items.map(\.name)), Set(names + ["empty.txt"]))
        XCTAssertEqual(items.first { $0.name == "empty.txt" }?.size, 0)
        XCTAssertTrue(items.allSatisfy { !$0.isDirectory })
    }

    func testDownloadsListOnlyDirectChildrenAndMeasureWholeFolders() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let downloads = home.appendingPathComponent("Downloads")
        let folder = downloads.appendingPathComponent("photos")
        let nested = folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads.appendingPathComponent("empty-folder"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data([1]).write(to: folder.appendingPathComponent("small.webp"))
        try Data([1, 2, 3]).write(to: nested.appendingPathComponent("photo.png"))
        try Data([9]).write(to: downloads.appendingPathComponent("top.jpg"))
        let items = await ScanService(homeDirectory: home).scanDownloads()
        XCTAssertEqual(Set(items.map(\.name)), ["photos", "empty-folder", "top.jpg"])
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy {
            $0.pathURL.deletingLastPathComponent().resolvingSymlinksInPath().path == downloads.resolvingSymlinksInPath().path
        })
        let directory = try XCTUnwrap(items.first { $0.name == "photos" })
        XCTAssertTrue(directory.isDirectory)
        XCTAssertEqual(directory.size, 4)
        XCTAssertEqual(items.first { $0.name == "empty-folder" }?.size, 0)
        XCTAssertEqual(items.first { $0.name == "top.jpg" }?.size, 1)
    }
}
