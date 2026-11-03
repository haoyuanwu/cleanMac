import XCTest
@testable import cleanMac

final class DownloadInventoryTests: XCTestCase {
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
