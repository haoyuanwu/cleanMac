import XCTest
@testable import cleanMac

final class DevelopmentStorageTests: XCTestCase {
    private var home: URL!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }
    private func write(_ relative: String) throws {
        let url = home.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: url)
    }
    func testPackagesOnlyIncludeCachesNotCredentialsOrInstalledBinaries() throws {
        try write(".npm/_cacache/content/file")
        try write(".npmrc")
        try write(".cargo/bin/tool")
        try write(".gradle/gradle.properties")
        let report = DevelopmentStorageScanner.scan(.packages, home: home, environment: [:], includeDocker: false)
        XCTAssertEqual(report.entries.map(\.file.path), [home.path + "/.npm/_cacache"])
        XCTAssertTrue(report.entries[0].cleanable)
        XCTAssertEqual(report.entries[0].file.size, 7)
    }
    func testModelsToolchainsAndAgentDataAreReadOnly() throws {
        for name in [".ollama/models/file", ".rustup/toolchains/file", ".codex/sessions/file", ".cursor/extensions/file"] { try write(name) }
        let report = DevelopmentStorageScanner.scan(.ai, home: home, environment: [:], includeDocker: false)
        XCTAssertEqual(report.entries.count, 4)
        XCTAssertTrue(report.entries.allSatisfy { !$0.cleanable })
    }
    func testProjectMarkersAndNestedArtifactsAreCountedOnce() throws {
        try write("Projects/web/package.json")
        try write("Projects/web/node_modules/nested/node_modules/file")
        try write("Projects/web/.next/cache/file")
        try write("Documents/notes/build/important.txt")
        try write("Desktop/ordinary.txt")
        try write("Documents/swift/Package.swift")
        try write("Documents/swift/.build/file")
        let report = DevelopmentStorageScanner.scan(.projects, home: home, includeDocker: false)
        XCTAssertEqual(report.entries.count, 3)
        XCTAssertEqual(Set(report.entries.map(\.file.name)), ["node_modules", ".next", ".build"])
        XCTAssertTrue(report.entries.allSatisfy(\.cleanable))
        XCTAssertFalse(DevelopmentStorageScanner.isCleanablePath(home.path + "/Documents/notes/build", home: home))
        XCTAssertTrue(DevelopmentStorageScanner.isCleanablePath(home.path + "/Projects/web/node_modules", home: home))
    }
    func testSymlinkRootAndProjectArtifactAreNotFollowed() throws {
        try write("outside/package.json")
        try write("outside/node_modules/file")
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Projects"), withDestinationURL: home.appendingPathComponent("outside"))
        try write("Desktop/app/package.json")
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Desktop/app/node_modules"), withDestinationURL: home.appendingPathComponent("outside/node_modules"))
        XCTAssertTrue(DevelopmentStorageScanner.scan(.projects, home: home, includeDocker: false).entries.isEmpty)
        XCTAssertFalse(DevelopmentStorageScanner.isCleanablePath(home.path + "/Desktop/app/node_modules", home: home))
    }
    func testVirtualDisksAreInventoryNotReclaimable() throws {
        try write("Parallels/Linux.pvm/disk.hdd")
        let report = DevelopmentStorageScanner.scan(.containers, home: home, includeDocker: false)
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertFalse(report.entries[0].cleanable)
        XCTAssertNil(report.docker)
    }
    func testEnvironmentModelPathsDeduplicateAndDoNotScanHFToken() throws {
        try write("models/hub/weights")
        try write("models/token")
        let report = DevelopmentStorageScanner.scan(.ai, home: home,
            environment: ["HF_HOME": home.path + "/models", "OLLAMA_MODELS": home.path + "/models/hub"], includeDocker: false)
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertEqual(report.entries[0].file.size, 7)
        XCTAssertFalse(report.entries[0].cleanable)
    }
    func testWhitelistedDescendantPreventsCleaningParentCache() throws {
        try write(".npm/_cacache/keep/file")
        let keep = home.path + "/.npm/_cacache/keep"
        UserWhitelist.add(keep)
        defer { UserWhitelist.remove(keep) }
        let report = DevelopmentStorageScanner.scan(.packages, home: home, environment: [:], includeDocker: false)
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertFalse(report.entries[0].cleanable)
        XCTAssertFalse(DevelopmentStorageScanner.isCleanablePath(home.path + "/.npm/_cacache", home: home))
    }
    func testCancelledScanDoesNotClaimCompleteResults() async {
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return DevelopmentStorageScanner.scan(.projects, home: home, includeDocker: false)
        }
        task.cancel()
        let report = await task.value
        XCTAssertEqual(report.diagnostics.status, .cancelled)
        XCTAssertTrue(report.entries.isEmpty)
    }

    private func entry(_ name: String, cleanable: Bool = true) -> DevelopmentStorageEntry {
        .init(file: FileItem(path: home.path + "/" + name, name: name, size: 7, modificationDate: nil, isDirectory: true),
              owner: name, detail: "fixture", cleanable: cleanable)
    }
    func testFilteringDropsHiddenSelectionAndNeverRestoresItAutomatically() {
        let first = entry("one"), second = entry("two")
        let original: Set<String> = [first.id, second.id]
        let filtered = DevelopmentStorageSelection.reconcile(original, visible: [first])
        XCTAssertEqual(filtered, [first.id])
        XCTAssertEqual(DevelopmentStorageSelection.reconcile(filtered, visible: [first, second]), [first.id])
        XCTAssertEqual(DevelopmentStorageSelection.targets(original, visible: [first]).map(\.id), [first.id])
    }
    func testReadOnlyEntriesCannotEnterReviewEvenIfTheirIDsWereSelected() {
        let cache = entry("cache"), model = entry("model", cleanable: false)
        XCTAssertEqual(DevelopmentStorageSelection.targets([cache.id, model.id], visible: [cache, model]).map(\.id), [cache.id])
    }
    func testReviewKeepsFrozenTargetsWhenSelectionChanges() {
        let first = entry("one"), second = entry("two")
        var selection: Set<String> = [first.id]
        let review = DevelopmentStorageReview(kind: .packages, entries: DevelopmentStorageSelection.targets(selection, visible: [first, second]))
        selection = [second.id]
        XCTAssertEqual(review.entries.map(\.id), [first.id])
        XCTAssertEqual(review.totalSize, 7)
        XCTAssertEqual(DevelopmentStorageSelection.targets(selection, visible: [first, second]).map(\.id), [second.id])
    }
    func testNewWhitelistExcludesPreviouslySelectedDirectoryAndItsParent() {
        let cache = entry("cache")
        UserWhitelist.add(cache.id + "/keep")
        defer { UserWhitelist.remove(cache.id + "/keep") }
        XCTAssertTrue(DevelopmentStorageSelection.targets([cache.id], visible: [cache]).isEmpty)
    }

    func testAICachesAreChildrenOfReadOnlySoftwareAndCountedOnce() throws {
        for file in [".codex/tmp/a", ".codex/cache/a", ".codex/logs/a", ".codex/sessions/tmp/a", ".codex/plugins/cache/a"] { try write(file) }
        let report = DevelopmentStorageScanner.scan(.ai, home: home, environment: [:], includeDocker: false)
        let codex = try XCTUnwrap(report.entries.first { $0.owner == "Codex" })
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertFalse(codex.cleanable)
        XCTAssertEqual(codex.file.size, 35)
        XCTAssertEqual(Set(codex.children.map(\.file.name)), ["tmp", "cache", "logs"])
        XCTAssertTrue(codex.children.allSatisfy(\.cleanable))
        XCTAssertEqual(DevelopmentStorageSelection.eligible(codex.descendants).count, 3)
    }
    func testAITransientValidationExcludesSessionPluginsModelsAndSoftwareRoots() throws {
        for file in [".codex/tmp/a", ".codex/sessions/tmp/a", ".codex/plugins/cache/a", ".ollama/models/cache/a", ".rustup/toolchains/logs/a"] { try write(file) }
        XCTAssertTrue(DevelopmentStorageScanner.isCleanablePath(home.path + "/.codex/tmp", home: home))
        for path in [".codex", ".codex/sessions/tmp", ".codex/plugins/cache", ".ollama/models/cache", ".rustup/toolchains/logs", ".codex/my-cache"] {
            XCTAssertFalse(DevelopmentStorageScanner.isCleanablePath(home.path + "/" + path, home: home), path)
        }
    }
    func testEditorCachesInKnownWrapperAreFoundWithoutWorkspaceData() throws {
        for file in ["Library/Application Support/Cursor/Code Cache/a", "Library/Application Support/Cursor/logs/a", "Library/Application Support/Cursor/User/Cache/a", "Library/Application Support/Cursor/User/workspaceStorage/cache/a"] { try write(file) }
        let report = DevelopmentStorageScanner.scan(.ai, home: home, environment: [:], includeDocker: false)
        let cursor = try XCTUnwrap(report.entries.first { $0.owner == "Cursor" })
        XCTAssertEqual(cursor.children.count, 3)
        for child in cursor.children { XCTAssertTrue(DevelopmentStorageScanner.isCleanablePath(child.id, home: home)) }
        XCTAssertFalse(DevelopmentStorageScanner.isCleanablePath(home.path + "/Library/Application Support/Cursor/User/workspaceStorage/cache", home: home))
    }
    func testAITransientSymlinksAndWhitelistRemainProtected() throws {
        try write("outside/a")
        try write(".codex/logs/keep/a")
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent(".codex/tmp"), withDestinationURL: home.appendingPathComponent("outside"))
        let keep = home.path + "/.codex/logs/keep"
        UserWhitelist.add(keep)
        defer { UserWhitelist.remove(keep) }
        let report = DevelopmentStorageScanner.scan(.ai, home: home, environment: [:], includeDocker: false)
        let codex = try XCTUnwrap(report.entries.first)
        XCTAssertEqual(codex.children.map(\.file.name), ["logs"])
        XCTAssertFalse(codex.children[0].cleanable)
        XCTAssertFalse(DevelopmentStorageScanner.isCleanablePath(home.path + "/.codex/tmp", home: home))
        XCTAssertFalse(DevelopmentStorageScanner.isCleanablePath(home.path + "/.codex/logs", home: home))
    }
    func testRemovingChildUpdatesParentTotalAndPreservesModelData() throws {
        try write(".codex/cache/a")
        try write(".codex/sessions/a")
        let report = DevelopmentStorageScanner.scan(.ai, home: home, environment: [:], includeDocker: false)
        let codex = try XCTUnwrap(report.entries.first)
        let updated = try XCTUnwrap(codex.removing([codex.children[0].id]))
        XCTAssertEqual(updated.file.size, 7)
        XCTAssertTrue(updated.children.isEmpty)
        XCTAssertFalse(updated.cleanable)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.path + "/.codex/sessions/a"))
    }
    func testAISearchAndCollapsedSoftwareLimitSelectionToVisibleCaches() throws {
        try write(".codex/cache/a")
        try write(".codex/logs/a")
        let report = DevelopmentStorageScanner.scan(.ai, home: home, environment: [:], includeDocker: false)
        let root = try XCTUnwrap(report.entries.first)
        let selection = Set(root.children.map(\.id))
        let filtered = try XCTUnwrap(root.matching("/logs"))
        XCTAssertEqual(DevelopmentStorageSelection.targets(selection, visible: filtered.descendants).map(\.file.name), ["logs"])
        XCTAssertTrue(DevelopmentStorageSelection.reconcile(selection, visible: []).isEmpty)
        XCTAssertNil(root.matching("not-a-real-directory"))
    }

}
