import XCTest
@testable import cleanMac

final class CleaningHistoryTests: XCTestCase {
    private var root: URL!
    private var trash: URL!
    private var original: URL!
    private var store: CleaningHistoryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        trash = root.appendingPathComponent("Trash")
        original = root.appendingPathComponent("original/file")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        store = CleaningHistoryStore(fileURL: root.appendingPathComponent("history.json"), testTrashRoot: trash)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func record(directory: Bool = false) throws -> CleaningRecord {
        let destination = trash.appendingPathComponent("moved")
        if directory {
            try FileManager.default.createDirectory(at: destination.appendingPathComponent("nested"), withIntermediateDirectories: true)
            try Data("before".utf8).write(to: destination.appendingPathComponent("nested/file"))
        } else { try Data("before".utf8).write(to: destination) }
        return store.record(path: original.path, size: 6, category: "测试", state: .movedToTrash, trashPath: destination.path)
    }

    func testRestoreAndPersistentState() throws {
        let entry = try record()
        try store.restore(entry.id)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "before")
        let reloaded = CleaningHistoryStore(fileURL: root.appendingPathComponent("history.json"), testTrashRoot: trash)
        XCTAssertEqual(reloaded.records.first?.state, .restored)
        XCTAssertThrowsError(try reloaded.restore(entry.id))
    }
    func testConflictNeverOverwritesOriginal() throws {
        let entry = try record()
        try Data("new original".utf8).write(to: original)
        XCTAssertThrowsError(try store.restore(entry.id))
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "new original")
        XCTAssertTrue(FileManager.default.fileExists(atPath: entry.trashPath!))
    }
    func testChangedTrashFileCannotBeRestored() throws {
        let entry = try record()
        try Data("changed payload".utf8).write(to: URL(fileURLWithPath: entry.trashPath!))
        XCTAssertThrowsError(try store.restore(entry.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
    }
    func testChangedNestedFileCannotBeRestored() throws {
        let entry = try record(directory: true)
        try Data("changed payload".utf8).write(to: URL(fileURLWithPath: entry.trashPath!).appendingPathComponent("nested/file"))
        XCTAssertThrowsError(try store.restore(entry.id))
    }
    func testMissingTrashEntryReportsFailure() throws {
        let entry = try record()
        try FileManager.default.removeItem(atPath: entry.trashPath!)
        XCTAssertThrowsError(try store.restore(entry.id))
    }
    func testPermanentDeletionIsNotRestorable() {
        let entry = store.record(path: original.path, size: 6, category: "测试", state: .permanentlyDeleted)
        XCTAssertNil(entry.trashPath)
        XCTAssertThrowsError(try store.restore(entry.id))
    }
    func testChangedParentSymlinkCannotRedirectRestore() throws {
        let entry = try record()
        let parent = original.deletingLastPathComponent()
        try FileManager.default.removeItem(at: parent)
        try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: trash)
        XCTAssertThrowsError(try store.restore(entry.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: entry.trashPath!))
    }
    func testCorruptHistoryIsPreservedAndErrorIsVisible() throws {
        let url = root.appendingPathComponent("invalid.json")
        let data = Data("invalid json".utf8)
        try data.write(to: url)
        let invalid = CleaningHistoryStore(fileURL: url, testTrashRoot: trash)
        XCTAssertNotNil(invalid.persistenceError)
        invalid.record(path: original.path, size: 0, category: "测试", state: .failed)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
}
