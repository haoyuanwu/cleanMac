import XCTest
@testable import cleanMac

final class CacheRuleTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "cleanMac.rules-tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }
    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: root)
    }

    private func data(path: String = "blob_storage", version: String = "test.1", kind: String = "applicationSupport") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "version": version, "title": "测试规则",
            "rules": [["id": "test-blob", "title": "临时文件", "bundleIdentifiers": ["com.example.Editor"],
                       "rootKinds": [kind], "relativePaths": [path], "reason": "测试归属", "impact": "请退出软件", "risk": "sensitive",
                       "sources": ["https://example.com/definition"]]]
        ])
    }
    private func catalog(path: String = "blob_storage", version: String = "test.1") throws -> CacheRuleCatalog {
        try CacheRuleCatalog.decode(data(path: path, version: version))
    }
    private func dataRoot(id: String = "com.example.Editor", kind: CacheDataRootKind = .applicationSupport) -> ApplicationCacheScanner.DataRoot {
        .init(url: root, owner: .init(id: id, name: "Editor", path: nil), isCacheRoot: false, kind: kind)
    }
    private func write(_ path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: url)
    }

    func testRuleDiscoversNonCacheNameAndRetainsExplanationAndRisk() throws {
        try write("blob_storage/session/blob")
        let rules = try catalog()
        XCTAssertTrue(ApplicationCacheScanner.cacheItems(in: [dataRoot()], catalog: .baseline).isEmpty)
        let items = ApplicationCacheScanner.cacheItems(in: [dataRoot()], catalog: rules)
        XCTAssertEqual(items.count, 1)
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.cacheRuleMatch?.ruleID, "test-blob")
        XCTAssertEqual(item.cacheRuleMatch?.version, "test.1")
        XCTAssertEqual(item.cacheApplication?.id, "com.example.Editor")
        XCTAssertEqual(SafetyWhitelist.annotated(item, category: .applicationCache).riskLevel, .sensitive)
        XCTAssertTrue(SmartCleanPlan.build(from: [.applicationCache: .init(category: .applicationCache, items: [item])]).isEmpty)
    }

    func testRuleDoesNotMatchAnotherBundleOrDataRootKind() throws {
        try write("blob_storage/session/blob")
        let rules = try catalog()
        XCTAssertTrue(ApplicationCacheScanner.cacheItems(in: [dataRoot(id: "com.example.Editor.Other")], catalog: rules).isEmpty)
        XCTAssertTrue(ApplicationCacheScanner.cacheItems(in: [dataRoot(kind: .container)], catalog: rules).isEmpty)
    }

    func testCatalogRejectsTraversalAbsoluteWildcardAndProtectedDataPaths() throws {
        for path in ["", "/tmp/blob", "../blob", "a/../../blob", "a//blob", "./blob", "*/blob", "a?.bin", "Documents/blob_storage", "Local Storage", "IndexedDB", "Cookies", "Storage", "Resource.app/blob_storage", "a\\b"] {
            XCTAssertThrowsError(try CacheRuleCatalog.decode(data(path: path)), path)
        }
        XCTAssertNoThrow(try CacheRuleCatalog.decode(data(path: "Storage", kind: "caches")))
    }

    func testSymlinkTargetAndAncestorAreRejected() throws {
        try write("outside/session/blob")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("blob_storage"), withDestinationURL: root.appendingPathComponent("outside"))
        XCTAssertTrue(CacheRuleMatcher.matches(in: dataRoot(), catalog: try catalog()).isEmpty)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: root.appendingPathComponent("outside"))
        XCTAssertTrue(CacheRuleMatcher.matches(in: dataRoot(), catalog: try catalog(path: "linked/session")).isEmpty)
    }

    func testPackagesAndAppBundleResourcesAreRejected() throws {
        try write("Archive.bundle/blob_storage/session/blob")
        XCTAssertTrue(CacheRuleMatcher.matches(in: dataRoot(), catalog: try catalog(path: "Archive.bundle/blob_storage")).isEmpty)
        let app = root.appendingPathComponent("Resource.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: app.appendingPathComponent("cache.bin"))
        let appRoot = ApplicationCacheScanner.DataRoot(url: app, owner: dataRoot().owner, isCacheRoot: false)
        XCTAssertTrue(ApplicationCacheScanner.cacheItems(in: [appRoot], catalog: try catalog()).isEmpty)
    }

    func testRuleChangeInvalidatesNegativeCacheAndRejectsOldScanUpdates() throws {
        try write("blob_storage/session/blob")
        let ignores = CacheScanIgnoreStore(defaults: defaults)
        XCTAssertTrue(ApplicationCacheScanner.cacheItems(in: [dataRoot()], ignoreStore: ignores, catalog: .baseline).isEmpty)
        XCTAssertEqual(ignores.allRecords.count, 1)
        let oldRevision = ignores.revision
        let oldRecords = ignores.allRecords
        XCTAssertEqual(ApplicationCacheScanner.cacheItems(in: [dataRoot()], ignoreStore: ignores, catalog: try catalog()).count, 1)
        XCTAssertTrue(ignores.allRecords.isEmpty)
        ignores.apply(emptyRoots: oldRecords, rescannedPaths: [root.path], expectedRevision: oldRevision)
        XCTAssertTrue(ignores.allRecords.isEmpty)
    }

    func testContentChangeWithSameVersionAlsoInvalidatesIgnores() throws {
        let first = try catalog()
        let second = try catalog(path: "Transient")
        XCTAssertEqual(first.version, second.version)
        XCTAssertNotEqual(first.fingerprint, second.fingerprint)
        let ignores = CacheScanIgnoreStore(defaults: defaults)
        ignores.prepare(for: first.fingerprint)
        let record = try XCTUnwrap(CacheScanIgnoreStore.record(for: root.path, applicationName: "Editor", at: Date()))
        ignores.apply(emptyRoots: [record], rescannedPaths: [root.path], expectedRevision: ignores.revision)
        XCTAssertTrue(ignores.shouldSkip(root.path))
        ignores.prepare(for: second.fingerprint)
        XCTAssertFalse(ignores.shouldSkip(root.path))
    }

    func testRollbackPersistsAndRemovesDedicatedMatches() throws {
        try write("blob_storage/session/blob")
        let bytes = try data()
        let store = CacheRuleStore(defaults: defaults, catalogData: [bytes])
        XCTAssertEqual(store.activeCatalog.version, "test.1")
        XCTAssertEqual(ApplicationCacheScanner.cacheItems(in: [dataRoot()], catalog: store.activeCatalog).count, 1)
        store.activate(CacheRuleCatalog.baseline.version)
        let reloaded = CacheRuleStore(defaults: defaults, catalogData: [bytes])
        XCTAssertEqual(reloaded.activeCatalog.version, CacheRuleCatalog.baseline.version)
        XCTAssertTrue(ApplicationCacheScanner.cacheItems(in: [dataRoot()], catalog: reloaded.activeCatalog).isEmpty)
        reloaded.activate("not-installed")
        XCTAssertEqual(reloaded.activeCatalog.version, CacheRuleCatalog.baseline.version)
    }

    func testInvalidOrMissingSavedCatalogFallsBackVisibly() throws {
        let invalid = CacheRuleStore(defaults: defaults, catalogData: [Data("bad json".utf8)])
        XCTAssertEqual(invalid.activeCatalog.version, CacheRuleCatalog.baseline.version)
        XCTAssertFalse(invalid.loadErrors.isEmpty)
        defaults.set("future-version", forKey: "com.cleanMac.cacheRules.version")
        let missing = CacheRuleStore(defaults: defaults, catalogData: [try data()])
        XCTAssertEqual(missing.activeCatalog.version, CacheRuleCatalog.baseline.version)
        XCTAssertFalse(missing.loadErrors.isEmpty)
    }

    func testUnsupportedSchemaAndDuplicateRuleIDsAreRejected() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data()) as? [String: Any])
        json["schemaVersion"] = 2
        XCTAssertThrowsError(try CacheRuleCatalog.decode(JSONSerialization.data(withJSONObject: json)))
        json["schemaVersion"] = 1
        let rules = try XCTUnwrap(json["rules"] as? [[String: Any]])
        json["rules"] = rules + rules
        XCTAssertThrowsError(try CacheRuleCatalog.decode(JSONSerialization.data(withJSONObject: json)))
    }

    func testReplacementBySymlinkAfterScanFailsDeletionRevalidation() throws {
        try write("blob_storage/session/blob")
        let item = try XCTUnwrap(ApplicationCacheScanner.cacheItems(in: [dataRoot()], catalog: try catalog()).first)
        XCTAssertTrue(CacheRuleMatcher.isWithinRecordedRoot(item))
        try FileManager.default.moveItem(at: root.appendingPathComponent("blob_storage"), to: root.appendingPathComponent("moved"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("blob_storage"), withDestinationURL: root.appendingPathComponent("moved"))
        XCTAssertFalse(CacheRuleMatcher.isWithinRecordedRoot(item))
        XCTAssertEqual(DeleteDryRun.validate(items: [item]).blocked.count, 1)
    }

    func testBundledCatalogIsValidAndKeepsPersistentStorageOut() throws {
        let resource = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("cleanMac/Resources/cache-rules-2026.10.28.1.json")
        let bundled = try CacheRuleCatalog.decode(Data(contentsOf: resource))
        XCTAssertEqual(bundled.rules.count, 2)
        XCTAssertTrue(bundled.rules.allSatisfy { !$0.relativePaths.contains("Storage") })
    }
}
