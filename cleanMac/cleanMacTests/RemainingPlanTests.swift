import XCTest
@testable import cleanMac

final class RemainingPlanTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var library: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        home = root.appendingPathComponent("Home")
        library = root.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    @discardableResult private func write(_ relative: String, _ data: Data = Data("fixture".utf8)) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }
    private func json(_ relative: String, _ object: [String: Any]) throws -> URL {
        try write(relative, JSONSerialization.data(withJSONObject: object))
    }
    private func plist(_ relative: String, _ object: [String: Any]) throws -> URL {
        try write(relative, PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0))
    }
    private func file(_ url: URL, size: Int64? = nil) throws -> FileItem {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileItem(path: url.path, name: url.lastPathComponent, size: size ?? (attrs[.size] as? Int64 ?? 0), modificationDate: attrs[.modificationDate] as? Date, isDirectory: false)
    }
    private func dataRoot() throws -> ApplicationCacheScanner.DataRoot {
        let url = root.appendingPathComponent("Data")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return .init(url: url, owner: .init(id: "com.test.Editor", name: "Editor", path: nil), isCacheRoot: false)
    }
    private func token(_ session: UUID = UUID(), revision: UInt64 = 0, epoch: UInt64 = 0, available: Bool = true) -> CacheEventToken {
        CacheEventToken(session: session, epoch: epoch, revision: revision, available: available)
    }

    func testCategoryCancellationStopsDetachedWorkWithoutCancellingCaller() async {
        let collector = ScanDiagnosticsCollector()
        let parent = Task {
            await ScanContext.$diagnostics.withValue(collector) {
                await ScanTask.run {
                    while !Task.isCancelled { Thread.sleep(forTimeInterval: 0.001) }
                    return Task.isCancelled
                }
            }
        }
        try? await Task.sleep(for: .milliseconds(20))
        collector.requestCancellation()
        let stopped = await parent.value
        XCTAssertTrue(stopped)
        XCTAssertFalse(parent.isCancelled)
        XCTAssertEqual(collector.snapshot(finished: true).status, .cancelled)
    }

    func testSmallMetadataFilesDoNotDisplayAsZeroSize() {
        XCTAssertEqual(FileSizeFormatter.string(fromByteCount: 0), "0 B")
        XCTAssertEqual(FileSizeFormatter.string(fromByteCount: 1), "1 B")
        XCTAssertEqual(FileSizeFormatter.string(fromByteCount: 1023), "1023 B")
        XCTAssertNotEqual(FileSizeFormatter.string(fromByteCount: 1024), "0 B")
    }

    func testLaunchPlistShowsDeclarationAndMissingFileWithoutMalwareVerdict() throws {
        let url = try plist("Home/Library/LaunchAgents/test.plist", ["Label": "com.test.agent", "ProgramArguments": ["/definitely-missing-cleanmac-fixture", "--flag"]])
        let item = try XCTUnwrap(StartupInspectionService.launchItem(url, source: "用户 LaunchAgents"))
        XCTAssertEqual(item.name, "com.test.agent")
        XCTAssertTrue(item.notes.contains("文件不存在"))
        XCTAssertTrue(item.notes.contains { $0.contains("不代表恶意") })
        XCTAssertTrue(item.notes.contains { $0.contains("/definitely-missing-cleanmac-fixture") })
    }
    func testLaunchSymlinkIsNotParsed() throws {
        let target = try plist("outside.plist", ["Label": "com.test.outside", "Program": "/bin/sh"])
        let link = root.appendingPathComponent("link.plist")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertNil(StartupInspectionService.launchItem(link, source: "test"))
    }
    func testLoginDumpParserSupportsFileURLsColonsAndDuplicateRecords() {
        let text = """
        #1:
        UUID: 1
        Name: Example: Helper
        Identifier: com.test.helper
        URL: file:///Applications/Example%20App.app
        Type: login item
        Disposition: enabled, allowed
        #2:
        UUID: 2
        Name: Example: Helper
        Identifier: com.test.helper
        URL: file:///Applications/Example%20App.app
        Type: login item
        """
        let items = StartupInspectionService.loginItems(from: text)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "Example: Helper")
        XCTAssertEqual(items.first?.path, "/Applications/Example App.app")
    }
    func testLoginItemsKeepDifferentUserScopesDistinct() {
        let records = StartupInspectionService.loginItems(from: "UID -2:\n#1:\nName: Same\nIdentifier: com.test.same\nURL: file:///missing\nUID 501:\n#1:\nName: Same\nIdentifier: com.test.same\nURL: file:///missing")
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.flatMap(\.notes).contains("用户范围 UID：-2"))
        XCTAssertTrue(records.flatMap(\.notes).contains("用户范围 UID：501"))
    }

    func testStartupScopeIncludesUserSystemAndOptionalAppleSources() throws {
        _ = try plist("Home/Library/LaunchAgents/user.plist", ["Label": "user", "Program": "/missing-a"])
        _ = try plist("Library/LaunchDaemons/system.plist", ["Label": "system", "Program": "/missing-b"])
        _ = try plist("Apple/LaunchAgents/apple.plist", ["Label": "apple", "Program": "/missing-c"])
        let without = StartupInspectionService.scan(home: home, systemLibrary: library, loginText: "", appleLibrary: root.appendingPathComponent("Apple"))
        let withApple = StartupInspectionService.scan(home: home, systemLibrary: library, loginText: "", includeAppleServices: true, appleLibrary: root.appendingPathComponent("Apple"))
        XCTAssertEqual(without.items.count, 2)
        XCTAssertEqual(withApple.items.count, 3)
    }
    func testLoginCommandHasBoundedWait() {
        let start = Date()
        let result = StartupInspectionService.loginDump(timeout: 0.02)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        if result.error != nil { XCTAssertTrue(result.text.isEmpty) }
    }
    func testPrivacyInspectionDoesNotExposeHistoryOrCookieContents() throws {
        let secret = "secret-site-url-and-cookie-token"
        _ = try write("Home/Library/Application Support/Google/Chrome/Default/History", Data(secret.utf8))
        _ = try write("Home/Library/Application Support/Google/Chrome/Default/Network/Cookies", Data(secret.utf8))
        let report = BrowserPrivacyService.scan(home: home, runningBundleIdentifiers: ["com.google.Chrome"])
        XCTAssertEqual(report.items.count, 3)
        XCTAssertFalse(report.items.flatMap(\.notes).joined().contains(secret))
        XCTAssertTrue(report.items.allSatisfy { $0.notes.contains { $0.contains("元数据") } })
        XCTAssertTrue(report.items.allSatisfy { $0.notes.contains { $0.contains("浏览器正在运行") } })
    }
    func testPrivacySharedHistoryDatabaseIncludesWALWithoutDoubleClaim() throws {
        _ = try write("Home/Library/Application Support/Microsoft Edge/Profile 1/History", Data(repeating: 1, count: 10))
        _ = try write("Home/Library/Application Support/Microsoft Edge/Profile 1/History-wal", Data(repeating: 1, count: 5))
        let items = BrowserPrivacyService.scan(home: home).items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.size == 15 })
        XCTAssertTrue(items.allSatisfy { $0.notes.contains { $0.contains("不能按两份相加") } })
    }
    func testFirefoxPlacesWarningIncludesBookmarks() throws {
        _ = try write("Home/Library/Application Support/Firefox/Profiles/test.default/places.sqlite")
        let items = BrowserPrivacyService.scan(home: home).items
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.notes.contains { $0.contains("书签") } })
    }
    func testPrivacySymlinkProfileIsExcluded() throws {
        let outside = try write("Outside/History")
        let base = home.appendingPathComponent("Library/Application Support/Google/Chrome")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: base.appendingPathComponent("Default"), withDestinationURL: outside.deletingLastPathComponent())
        XCTAssertTrue(BrowserPrivacyService.scan(home: home).items.isEmpty)
    }
    func testBrowserExtensionManifestIsParsedWithoutExecutingScripts() throws {
        let url = try json("Home/Library/Application Support/Google/Chrome/Default/Extensions/abc/1.0/manifest.json", ["name": "Test Extension", "version": "1.0", "background": ["service_worker": "/bin/sh"]])
        let items = ExtensionInventoryService.scan(home: home, sharedLibrary: library, applications: []).items
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.version, "1.0")
        XCTAssertEqual(items.first?.path, url.deletingLastPathComponent().path)
        XCTAssertTrue(items.first?.notes.contains { $0.contains("不执行") } == true)
    }
    func testEditorAndAudioPackagesAreGroupedAndRemainStatic() throws {
        _ = try json("Home/.vscode/extensions/publisher.test/package.json", ["name": "test", "publisher": "Publisher", "version": "2.0", "scripts": ["postinstall": "touch /not-executed"]])
        _ = try plist("Library/Audio/Plug-Ins/VST3/Example.vst3/Contents/Info.plist", ["CFBundleName": "Example", "CFBundleIdentifier": "com.test.audio", "CFBundleShortVersionString": "3.0"])
        let report = ExtensionInventoryService.scan(home: home, sharedLibrary: library, applications: [])
        XCTAssertEqual(report.items.count, 2)
        XCTAssertEqual(Set(report.items.map(\.owner)), ["Visual Studio Code", "音频宿主共享"])
        XCTAssertTrue(report.items.contains { $0.kind == "VST3" && $0.version == "3.0" })
    }
    func testSafariExtensionRecognizesExtensionPoint() throws {
        let url = try plist("Apps/Host.app/Contents/PlugIns/Safari.appex/Contents/Info.plist", ["CFBundleName": "Safari Test", "NSExtension": ["NSExtensionPointIdentifier": "com.apple.Safari.web-extension"]])
        let path = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
        let apps = [ApplicationCacheScanner.InstalledApplication(application: .init(id: "com.test.host", name: "Host", path: path), aliases: [])]
        let report = ExtensionInventoryService.scan(home: home, sharedLibrary: library, applications: apps)
        XCTAssertEqual(report.items.filter { $0.kind == "Safari 扩展" }.count, 1)
    }
    func testMalformedExtensionManifestReportsPartialInsteadOfCrashing() throws {
        _ = try write("Home/.vscode/extensions/broken/package.json", Data("invalid json".utf8))
        let report = ExtensionInventoryService.scan(home: home, sharedLibrary: library, applications: [])
        XCTAssertTrue(report.items.isEmpty)
        XCTAssertFalse(report.issues.isEmpty)
    }
    func testInspectionDeduplicatesIDsAndDistinguishesMissingExecutable() {
        let collector = ScanDiagnosticsCollector()
        let item = InspectionItem(id: "same", name: "a", owner: "b", kind: "c", path: "")
        XCTAssertEqual(InspectionFS.finish([item, item], collector: collector).items.count, 1)
        XCTAssertEqual(StartupInspectionService.presence(nil), "执行路径待解析")
    }

    func testCacheIndexReusesOnlyIdenticalSessionRulesAndDirectoryIdentity() throws {
        let data = try dataRoot()
        let url = try write("Data/cache.bin")
        let item = try file(url)
        let index = CacheScanIndex(fileURL: root.appendingPathComponent("index.json"))
        let before = token()
        index.remember(root: data, items: [item], rules: "rules-v1", before: before, after: before)
        XCTAssertEqual(index.reusable(root: data, rules: "rules-v1", token: before)?.count, 1)
        XCTAssertNil(index.reusable(root: data, rules: "rules-v2", token: before))
        XCTAssertNil(index.reusable(root: data, rules: "rules-v1", token: token()))
        XCTAssertNil(index.reusable(root: data, rules: "rules-v1", token: token(before.session, revision: 1)))
        XCTAssertNil(index.reusable(root: data, rules: "rules-v1", token: token(before.session, epoch: 1)))
    }
    func testCacheIndexDoesNotCommitWhenEventsArriveDuringScan() throws {
        let data = try dataRoot(), before = token()
        let index = CacheScanIndex(fileURL: root.appendingPathComponent("index.json"))
        index.remember(root: data, items: [], rules: "r", before: before, after: token(before.session, revision: 1))
        XCTAssertNil(index.reusable(root: data, rules: "r", token: before))
    }
    func testCacheIndexRejectsFileReplacementPermissionsAndExpiredResults() throws {
        let data = try dataRoot(), before = token()
        let url = try write("Data/cache.bin"), item = try file(root.appendingPathComponent("Data/cache.bin"))
        let index = CacheScanIndex(fileURL: root.appendingPathComponent("index.json"))
        index.remember(root: data, items: [item], rules: "r", before: before, after: before)
        XCTAssertNil(index.reusable(root: data, rules: "r", token: before, now: Date().addingTimeInterval(601)))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        XCTAssertNil(index.reusable(root: data, rules: "r", token: before))
    }
    func testCacheIndexUnavailableMonitorNeverReuses() throws {
        let data = try dataRoot(), unavailable = token(available: false)
        let index = CacheScanIndex(fileURL: root.appendingPathComponent("index.json"))
        index.remember(root: data, items: [], rules: "r", before: unavailable, after: unavailable)
        XCTAssertNil(index.reusable(root: data, rules: "r", token: unavailable))
    }
    func testComparisonKeepsLastCompleteBaselineAcrossPartialScan() throws {
        let index = CacheScanIndex(fileURL: root.appendingPathComponent("index.json"))
        let url = try write("Data/file"), item = try file(root.appendingPathComponent("Data/file"), size: 10)
        index.finish(items: [item], complete: true, reused: 0, rescanned: 1, liveRoots: [], rules: "r")
        index.finish(items: [], complete: false, reused: 0, rescanned: 1, liveRoots: [], rules: "r")
        XCTAssertFalse(index.lastComparison?.complete ?? true)
        index.finish(items: [try file(url, size: 15)], complete: true, reused: 0, rescanned: 1, liveRoots: [], rules: "r")
        XCTAssertEqual(index.lastComparison?.added, 0)
        XCTAssertEqual(index.lastComparison?.increasedBytes, 5)
    }
    func testRuleChangeResetsComparisonBaselineAndPersists() throws {
        let path = root.appendingPathComponent("index.json"), index = CacheScanIndex(fileURL: root.appendingPathComponent("index.json"))
        let url = try write("Data/file")
        index.finish(items: [try file(url)], complete: true, reused: 0, rescanned: 1, liveRoots: [], rules: "r1")
        index.finish(items: [try file(url, size: 99)], complete: true, reused: 0, rescanned: 1, liveRoots: [], rules: "r2")
        XCTAssertNil(index.lastComparison?.previousDate)
        XCTAssertNil(CacheScanIndex(fileURL: path).lastComparison?.previousDate)
    }
    func testComparisonAddedRemovedAndGrowthAreExplainable() throws {
        let index = CacheScanIndex(fileURL: root.appendingPathComponent("index.json"))
        let first = try file(write("Data/first"), size: 12), second = try file(write("Data/second"), size: 20)
        index.finish(items: [first], complete: true, reused: 0, rescanned: 1, liveRoots: [], rules: "r")
        index.finish(items: [second], complete: true, reused: 1, rescanned: 0, liveRoots: [], rules: "r")
        XCTAssertEqual(index.lastComparison?.added, 1)
        XCTAssertEqual(index.lastComparison?.removed, 1)
        XCTAssertEqual(index.lastComparison?.decreasedBytes, 12)
        XCTAssertEqual(index.lastComparison?.increasedBytes, 20)
        XCTAssertEqual(index.lastComparison?.growth.first?.paths, [second.path])
    }
    func testFilesystemEventLossAndPermissionReturnInvalidateEpoch() {
        let monitor = CacheEventMonitor.shared
        let path = root.path
        let initial = monitor.token(for: path)
        monitor.record(paths: [path + "/child"], eventLoss: false)
        XCTAssertNotEqual(initial, monitor.token(for: path))
        let changed = monitor.token(for: path)
        monitor.record(paths: [], eventLoss: true)
        XCTAssertNotEqual(changed.epoch, monitor.token(for: path).epoch)
        let prior = monitor.token(for: path)
        monitor.invalidateAll()
        XCTAssertNotEqual(prior.epoch, monitor.token(for: path).epoch)
    }
    func testForceFullRescanBypassesNegativeIgnores() throws {
        let data = try dataRoot()
        _ = try write("Data/settings.json")
        let suite = "cleanMac.fullscan-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let ignore = CacheScanIgnoreStore(defaults: defaults)
        XCTAssertTrue(ApplicationCacheScanner.cacheItems(in: [data], ignoreStore: ignore, catalog: .baseline).isEmpty)
        _ = try write("Data/nested/Cache/file")
        let record = CacheScanIgnoreStore.record(for: data.url.path, applicationName: "Editor", at: Date())!
        ignore.apply(emptyRoots: [record], rescannedPaths: [data.url.path], expectedRevision: ignore.revision)
        XCTAssertTrue(ApplicationCacheScanner.cacheItems(in: [data], ignoreStore: ignore, catalog: .baseline).isEmpty)
        XCTAssertEqual(ApplicationCacheScanner.cacheItems(in: [data], ignoreStore: ignore, catalog: .baseline, forceFull: true).count, 1)
    }
    func testLiveFilesystemEventsRefreshDeepCacheChangesAndAllowReuse() throws {
        let live = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/cleanMac-event-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: live.appendingPathComponent("GPUCache"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: live) }
        let monitor = CacheEventMonitor.shared
        _ = monitor.token(for: live.path)
        let url = live.appendingPathComponent("GPUCache/data")
        try Data(repeating: 1, count: 7).write(to: url)
        let dataRoot = ApplicationCacheScanner.DataRoot(url: live, owner: .init(id: "com.test.Live", name: "Live", path: nil), isCacheRoot: false)
        let index = CacheScanIndex(fileURL: root.appendingPathComponent("live-index.json"))
        let first = ApplicationCacheScanner.cacheItems(in: [dataRoot], catalog: .baseline, index: index, monitor: monitor)
        XCTAssertEqual(first.reduce(0) { $0 + $1.size }, 7)
        let current = monitor.token(for: live.path)
        if current.available {
            // 首次创建事件可在首次扫描之后送达，允许保守重扫至事件稳定。
            for _ in 0..<5 {
                let second = ApplicationCacheScanner.cacheItems(in: [dataRoot], catalog: .baseline, index: index, monitor: monitor)
                XCTAssertEqual(second.reduce(0) { $0 + $1.size }, 7)
                if index.lastComparison?.reusedRoots == 1 { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
            XCTAssertEqual(index.lastComparison?.reusedRoots, 1)
        }
        try Data(repeating: 2, count: 41).write(to: url)
        let third = ApplicationCacheScanner.cacheItems(in: [dataRoot], catalog: .baseline, index: index, monitor: monitor)
        XCTAssertEqual(third.reduce(0) { $0 + $1.size }, 41)
        XCTAssertEqual(index.lastComparison?.reusedRoots, 0)
        _ = ApplicationCacheScanner.cacheItems(in: [dataRoot], catalog: .baseline, index: index, monitor: monitor, forceFull: true)
        XCTAssertEqual(index.lastComparison?.reusedRoots, 0)
    }

    func testLocalSuggestionsRequireEvidenceAndDoNotTreatModificationAsUsage() throws {
        let url = try write("old.bin")
        let old = Date().addingTimeInterval(-200 * 86400)
        let item = FileItem(path: url.path, name: "old.bin", size: 200 * 1024 * 1024, modificationDate: old, isDirectory: false)
        let result = ScanResult(category: .largeFiles, items: [item])
        let insights = LocalSpaceInsights.build(results: [.largeFiles: result], comparison: nil, duplicates: [], accessDates: [:])
        XCTAssertEqual(insights.count, 1)
        XCTAssertTrue(insights[0].title.contains("修改"))
        XCTAssertTrue(insights[0].evidence.contains { $0.contains("不能证明实际未使用") })
    }
    func testCancelledScansDoNotProduceLargeFileOrCacheSuggestions() throws {
        let url = try write("old.bin")
        let old = Date().addingTimeInterval(-200 * 86400)
        let item = FileItem(path: url.path, name: "old.bin", size: 200 * 1024 * 1024, modificationDate: old, isDirectory: false)
        let diagnostic = ScanDiagnosticsCollector().snapshot(finished: true, cancelled: true)
        let result = ScanResult(category: .largeFiles, items: [item], diagnostics: diagnostic)
        XCTAssertTrue(LocalSpaceInsights.build(results: [.largeFiles: result], comparison: nil, duplicates: [], accessDates: [:]).isEmpty)
    }
    func testSpaceSuggestionsExcludeProtectedPathsAndCloudPlaceholders() {
        let date = Date().addingTimeInterval(-200 * 86400)
        let system = FileItem(path: "/System/Library/protected", name: "protected", size: 200 * 1024 * 1024, modificationDate: date, isDirectory: false)
        let cloud = FileItem(path: root.appendingPathComponent("cloud").path, name: "cloud", size: 200 * 1024 * 1024,
                             modificationDate: date, isDirectory: false, storage: .init(logicalBytes: 200 * 1024 * 1024, allocatedBytes: 0, cloudPlaceholderCount: 1))
        let result = ScanResult(category: .largeFiles, items: [system, cloud])
        XCTAssertTrue(LocalSpaceInsights.build(results: [.largeFiles: result], comparison: nil, duplicates: [], accessDates: [:]).isEmpty)
    }
    func testGrowthSuggestionsWaitForActiveScanAndIgnoreCleanedResults() {
        let comparison = CacheScanComparison(date: Date(), previousDate: Date().addingTimeInterval(-60), added: 1, removed: 0,
            increasedBytes: 100, decreasedBytes: 0, reusedRoots: 0, rescannedRoots: 1,
            growth: [.init(application: "Editor", bytes: 100, paths: [root.path])], complete: true)
        let active = ScanResult(category: .applicationCache, items: [], isScanning: true)
        let cleaned = ScanResult(category: .applicationCache, items: [], isCleaned: true)
        XCTAssertTrue(LocalSpaceInsights.build(results: [.applicationCache: active], comparison: comparison, duplicates: []).isEmpty)
        XCTAssertTrue(LocalSpaceInsights.build(results: [.applicationCache: cleaned], comparison: comparison, duplicates: []).isEmpty)
    }

    func testDuplicateSuggestionDisclosesPartialHashAndEvidence() throws {
        let a = try file(write("a")), b = try file(write("b"))
        let group = DuplicateFileScanner.DuplicateGroup(id: "g", size: 7, hash: "partial", files: [a, b])
        let insights = LocalSpaceInsights.build(results: [:], comparison: nil, duplicates: [group])
        XCTAssertEqual(insights.count, 1)
        XCTAssertTrue(insights[0].title.contains("疑似"))
        XCTAssertTrue(insights[0].evidence.contains { $0.contains("未保证整文件逐字节相同") })
    }
    func testStartupOverridesParseExplicitTrueAndFalse() {
        let values = StartupControlService.parseOverrides("disabled services = {\n \"com.example.off\" => true\n \"com.example.on\" => false\n invalid => maybe\n}")
        XCTAssertEqual(values, ["com.example.off": true, "com.example.on": false])
    }
    func testSoftwareAssociationUsesExactAppPathAndIdentifierBoundary() {
        let app = CacheApplication(id: "com.example.Editor", name: "Editor", path: "/Applications/Editor.app")
        XCTAssertEqual(InspectionSoftwareIdentity.application(path: "/Applications/Editor.app/Contents/MacOS/helper", identifier: nil, applications: [app]), app)
        XCTAssertNil(InspectionSoftwareIdentity.application(path: "/Applications/Editor.app-other/helper", identifier: "com.example.EditorOther.helper", applications: [app]))
        XCTAssertEqual(InspectionSoftwareIdentity.application(path: "/outside", identifier: "com.example.Editor.helper", applications: [app]), app)
    }
    func testStartupPolicyRejectsChangedLabelsAndUnsafePermissions() throws {
        let url = try plist("Home/Library/LaunchAgents/com.example.demo.plist", ["Label": "com.example.demo"])
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        var item = InspectionItem(id: "fixture", name: "demo", owner: "用户 LaunchAgents", kind: "LaunchAgent", path: url.path)
        item.startupLabel = "com.example.demo"
        XCTAssertFalse(StartupControlService.canControl(item, home: home))
        item.application = CacheApplication(id: "com.example.demo", name: "Demo", path: nil)
        XCTAssertTrue(StartupControlService.canControl(item, home: home))
        item.startupLabel = "com.example.changed"
        XCTAssertFalse(StartupControlService.canControl(item, home: home))
        item.startupLabel = "com.example.demo"
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: url.path)
        XCTAssertFalse(StartupControlService.canControl(item, home: home))
    }
    func testStartupPolicyRejectsSystemSymlinksAndAppleServices() throws {
        let url = try plist("Library/LaunchAgents/com.example.demo.plist", ["Label": "com.example.demo"])
        var item = InspectionItem(id: "fixture", name: "demo", owner: "系统级 LaunchAgents", kind: "LaunchAgent", path: url.path)
        item.startupLabel = "com.example.demo"
        XCTAssertFalse(StartupControlService.canControl(item, home: home))
        let link = home.appendingPathComponent("Library/LaunchAgents/link.plist")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        item = InspectionItem(id: "fixture", name: "demo", owner: "用户 LaunchAgents", kind: "LaunchAgent", path: link.path)
        item.startupLabel = "com.example.demo"
        XCTAssertFalse(StartupControlService.canControl(item, home: home))
        let apple = try plist("Home/Library/LaunchAgents/apple.plist", ["Label": "com.apple.example"])
        item = InspectionItem(id: "fixture", name: "demo", owner: "用户 LaunchAgents", kind: "LaunchAgent", path: apple.path)
        item.startupLabel = "com.apple.example"
        XCTAssertFalse(StartupControlService.canControl(item, home: home))
    }
    func testStartupPolicyUsesOnlyEnableDisableAndVerifiesResult() throws {
        let url = try plist("Home/Library/LaunchAgents/demo.plist", ["Label": "com.example.demo"])
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        var item = InspectionItem(id: "fixture", name: "demo", owner: "用户 LaunchAgents", kind: "LaunchAgent", path: url.path)
        item.startupLabel = "com.example.demo"
        item.application = CacheApplication(id: "com.example.demo", name: "Demo", path: nil)
        var calls: [[String]] = []
        let error = StartupControlService.setEnabled(false, item: item, home: home) { args in
            calls.append(args)
            return (0, args.first == "print-disabled" ? "disabled services = {\n\"com.example.demo\" => true\n}" : "")
        }
        XCTAssertNil(error)
        XCTAssertEqual(calls.map { $0[0] }, ["disable", "print-disabled"])
        XCTAssertTrue(calls[0][1].hasSuffix("/com.example.demo"))
        XCTAssertNotNil(StartupControlService.setEnabled(true, item: item, home: home) { _ in (1, "not allowed") })
        XCTAssertNotNil(StartupControlService.setEnabled(true, item: item, home: home) { _ in (0, "unparseable") })
    }
    func testEditorInventoryCarriesOwningApplicationIdentity() throws {
        _ = try json("Home/.vscode/extensions/demo/package.json", ["name": "demo", "version": "1", "publisher": "example"])
        let report = ExtensionInventoryService.scan(home: home, sharedLibrary: library, applications: [])
        let item = try XCTUnwrap(report.items.first { $0.name == "demo" })
        XCTAssertEqual(item.application?.id, "com.microsoft.VSCode")
        XCTAssertEqual(item.softwareName, "Visual Studio Code")
    }

    private func resourceUsage(cpu: Double? = 200, memory: UInt64 = 50) -> ApplicationResourceUsage {
        ApplicationResourceUsage(application: ResourceAppDescriptor(pid: 100, launchDate: Date(timeIntervalSince1970: 10), bundleID: "example", name: "Example", path: "/Applications/Example.app"), cpuPercent: cpu, memory: memory, processCount: 1)
    }
    func testResourceAlertWaitsForSustainedUsageAndRecovers() {
        var policy = ResourceAlertPolicy(cpuThreshold: 150, memoryThreshold: 100, duration: 15)
        XCTAssertTrue(policy.evaluate([resourceUsage()], now: 0).high.isEmpty)
        _ = policy.evaluate([resourceUsage()], now: 5)
        _ = policy.evaluate([resourceUsage()], now: 10)
        XCTAssertEqual(policy.evaluate([resourceUsage()], now: 15).notify.count, 1)
        XCTAssertTrue(policy.evaluate([resourceUsage(cpu: 10)], now: 20).high.isEmpty)
    }
    func testResourceAlertCooldownAndSnoozeDoNotConsumeNotification() {
        var policy = ResourceAlertPolicy(cpuThreshold: 150, memoryThreshold: 100, duration: 0, cooldown: 60)
        XCTAssertTrue(policy.evaluate([resourceUsage()], now: 0, notificationsEnabled: false).notify.isEmpty)
        XCTAssertEqual(policy.evaluate([resourceUsage()], now: 5).notify.count, 1)
        XCTAssertTrue(policy.evaluate([resourceUsage()], now: 10).notify.isEmpty)
        XCTAssertTrue(policy.evaluate([resourceUsage()], now: 70).notify.isEmpty)
        _ = policy.evaluate([resourceUsage(cpu: 1)], now: 75)
        XCTAssertEqual(policy.evaluate([resourceUsage()], now: 80).notify.count, 1)
    }
    func testResourceAlertSleepGapResetsSustainedDuration() {
        var policy = ResourceAlertPolicy(cpuThreshold: 150, memoryThreshold: 100, duration: 15)
        _ = policy.evaluate([resourceUsage()], now: 0)
        XCTAssertTrue(policy.evaluate([resourceUsage()], now: 100).high.isEmpty)
        _ = policy.evaluate([resourceUsage()], now: 105)
        _ = policy.evaluate([resourceUsage()], now: 110)
        XCTAssertEqual(policy.evaluate([resourceUsage()], now: 115).high.count, 1)
    }
    func testResourceMemoryGrowthCanTriggerWithoutCPUReading() {
        let gib: UInt64 = 1024 * 1024 * 1024
        var policy = ResourceAlertPolicy(memoryThreshold: 4 * gib)
        _ = policy.evaluate([resourceUsage(cpu: nil, memory: gib)], now: 0)
        for time in stride(from: 5.0, through: 30, by: 5) {
            XCTAssertTrue(policy.evaluate([resourceUsage(cpu: nil, memory: 5 * gib)], now: time).notify.isEmpty)
        }
        XCTAssertEqual(policy.evaluate([resourceUsage(cpu: nil, memory: 5 * gib)], now: 35).notify.first?.alertReason, "内存持续明显增长")
        XCTAssertTrue(policy.evaluate([], now: 40).high.isEmpty)
    }
    func testResourceAggregatorCountsHelpersOnceAndKeepsIndependentApp() {
        let a = resourceUsage().application
        let b = ResourceAppDescriptor(pid: 200, launchDate: a.launchDate, bundleID: "other", name: "Other", path: "/Applications/Other.app")
        let rows = [ResourceProcessSample(pid: 100, parent: 1, birth: 1, path: a.path + "/Contents/MacOS/app", cpuNanoseconds: 10, memory: 100),
                    ResourceProcessSample(pid: 101, parent: 100, birth: 2, path: a.path + "/Contents/helper", cpuNanoseconds: 10, memory: 20),
                    ResourceProcessSample(pid: 102, parent: 100, birth: 3, path: "/usr/bin/helper", cpuNanoseconds: 10, memory: 30),
                    ResourceProcessSample(pid: 200, parent: 100, birth: 4, path: b.path + "/Contents/MacOS/app", cpuNanoseconds: 10, memory: 50)]
        let result = ApplicationResourceReader.aggregate(applications: [a, b], current: rows, previous: [], elapsed: 5)
        XCTAssertEqual(result.first { $0.id == a.id }?.memory, 150)
        XCTAssertEqual(result.first { $0.id == a.id }?.processCount, 3)
        XCTAssertEqual(result.first { $0.id == b.id }?.memory, 50)
    }
    func testResourceCPUUsesDeltasAndIgnoresReusedPID() {
        let app = resourceUsage().application
        let old = ResourceProcessSample(pid: 100, parent: 1, birth: 1, path: app.path + "/app", cpuNanoseconds: 1_000_000_000, memory: 1)
        let next = ResourceProcessSample(pid: 100, parent: 1, birth: 1, path: old.path, cpuNanoseconds: 3_000_000_000, memory: 1)
        let result = ApplicationResourceReader.aggregate(applications: [app], current: [next], previous: [old], elapsed: 2)
        XCTAssertEqual(result.first?.cpuPercent, 100)
        let reused = ResourceProcessSample(pid: 100, parent: 1, birth: 99, path: old.path, cpuNanoseconds: 9_000_000_000, memory: 1)
        XCTAssertNil(ApplicationResourceReader.aggregate(applications: [app], current: [reused], previous: [old], elapsed: 2).first?.cpuPercent)
    }
    func testResourceAggregationRejectsPathPrefixCollisionAndUnknownCPUGap() {
        let app = resourceUsage().application
        let foreign = ResourceProcessSample(pid: 999, parent: 1, birth: 1, path: app.path + "-other/app", cpuNanoseconds: 1, memory: 1)
        XCTAssertEqual(ApplicationResourceReader.aggregate(applications: [app], current: [foreign], previous: [], elapsed: 1).first?.sampleAvailable, false)
        let row = ResourceProcessSample(pid: app.pid, parent: 1, birth: 1, path: app.path + "/app", cpuNanoseconds: 1, memory: 1)
        XCTAssertNil(ApplicationResourceReader.aggregate(applications: [app], current: [row], previous: [row], elapsed: 60).first?.cpuPercent)
    }
    func testResourceReaderCanSampleOwnProcessWithoutExecutingTools() {
        let rows = ApplicationResourceReader.processes()
        let own = rows.first { $0.pid == ProcessInfo.processInfo.processIdentifier }
        XCTAssertNotNil(own)
        XCTAssertGreaterThan(own?.memory ?? 0, 0)
    }

    func testResourceBurstRequiresBaselineAndConfirmationSample() {
        var policy = ResourceAlertPolicy(memoryThreshold: 1000)
        _ = policy.evaluate([resourceUsage(cpu: 10)], now: 0)
        for time in stride(from: 5.0, through: 30, by: 5) {
            XCTAssertTrue(policy.evaluate([resourceUsage(cpu: 600)], now: time).notify.isEmpty)
        }
        XCTAssertEqual(policy.evaluate([resourceUsage(cpu: 600)], now: 35).notify.first?.alertReason, "CPU 突增且持续偏高")
    }
    func testResourceStallRequiresRepeatedTimeoutAndClearsOnRecovery() {
        var policy = ResourceAlertPolicy(memoryThreshold: 1000)
        var usage = resourceUsage(cpu: 1); usage.responsiveness = .unresponsive
        for time in stride(from: 0.0, through: 25, by: 5) { XCTAssertTrue(policy.evaluate([usage], now: time).notify.isEmpty) }
        XCTAssertEqual(policy.evaluate([usage], now: 30).notify.first?.alertReason, "疑似无响应 · 连续响应超时")
        usage.responsiveness = .responsive
        XCTAssertTrue(policy.evaluate([usage], now: 35).high.isEmpty)
    }
    func testUnknownResponsivenessNeverReportedAsHang() {
        var policy = ResourceAlertPolicy(memoryThreshold: 1000)
        for time in [0.0, 5, 10, 15, 20] { XCTAssertTrue(policy.evaluate([resourceUsage(cpu: 1)], now: time).high.isEmpty) }
    }

    func testResourceContinuousEpisodeNeverReopensAfterCooldown() {
        var policy = ResourceAlertPolicy(cpuThreshold: 150, memoryThreshold: 1000, duration: 0, cooldown: 10)
        XCTAssertEqual(policy.evaluate([resourceUsage()], now: 0).notify.count, 1)
        for time in stride(from: 5.0, through: 40, by: 5) {
            XCTAssertTrue(policy.evaluate([resourceUsage()], now: time).notify.isEmpty)
        }
        _ = policy.evaluate([resourceUsage(cpu: 1)], now: 45)
        XCTAssertEqual(policy.evaluate([resourceUsage()], now: 50).notify.count, 1)
    }

    func testResourceOverviewRetainsUnreadableApplicationsWithoutClaimingZeroUsage() {
        let app = resourceUsage().application
        let result = ApplicationResourceReader.aggregate(applications: [app], current: [], previous: [], elapsed: 5)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.application.id, app.id)
        XCTAssertEqual(result.first?.sampleAvailable, false)
        XCTAssertNil(result.first?.cpuPercent)
        XCTAssertEqual(result.first?.processCount, 0)
    }

    func testResourceDefaultIgnoresBriefCPUAndModerateSustainedUsage() {
        var policy = ResourceAlertPolicy(memoryThreshold: 1000)
        for time in stride(from: 0.0, through: 120, by: 5) {
            XCTAssertTrue(policy.evaluate([resourceUsage(cpu: time < 20 ? 600 : 200)], now: time).notify.isEmpty)
        }
    }
    func testResourceDefaultSteadyCPURequiresFullMinute() {
        var policy = ResourceAlertPolicy(memoryThreshold: 1000)
        for time in stride(from: 0.0, through: 55, by: 5) {
            XCTAssertTrue(policy.evaluate([resourceUsage(cpu: 500)], now: time).notify.isEmpty)
        }
        XCTAssertEqual(policy.evaluate([resourceUsage(cpu: 500)], now: 60).notify.count, 1)
    }
    func testResourceStableLargeMemoryNeverTriggers() {
        let gib: UInt64 = 1024 * 1024 * 1024
        var policy = ResourceAlertPolicy(memoryThreshold: 4 * gib)
        for time in stride(from: 0.0, through: 300, by: 5) {
            XCTAssertTrue(policy.evaluate([resourceUsage(cpu: 10, memory: 12 * gib)], now: time).high.isEmpty)
        }
    }
    func testResourceMemoryGrowthRequiresThresholdAndIgnoresSleepGap() {
        let gib: UInt64 = 1024 * 1024 * 1024
        var policy = ResourceAlertPolicy(memoryThreshold: 4 * gib)
        _ = policy.evaluate([resourceUsage(cpu: nil, memory: gib)], now: 0)
        for time in stride(from: 5.0, through: 40, by: 5) {
            XCTAssertTrue(policy.evaluate([resourceUsage(cpu: nil, memory: 3 * gib)], now: time).high.isEmpty)
        }
        for time in stride(from: 100.0, through: 200, by: 5) {
            XCTAssertTrue(policy.evaluate([resourceUsage(cpu: nil, memory: 8 * gib)], now: time).high.isEmpty)
        }
    }
    func testResourceCPURecoveryBreaksBurstConfirmation() {
        var policy = ResourceAlertPolicy(memoryThreshold: 1000)
        _ = policy.evaluate([resourceUsage(cpu: 10)], now: 0)
        for time in stride(from: 5.0, through: 25, by: 5) {
            XCTAssertTrue(policy.evaluate([resourceUsage(cpu: 600)], now: time).notify.isEmpty)
        }
        _ = policy.evaluate([resourceUsage(cpu: 10)], now: 30)
        for time in stride(from: 35.0, through: 60, by: 5) {
            XCTAssertTrue(policy.evaluate([resourceUsage(cpu: 600)], now: time).notify.isEmpty)
        }
        XCTAssertEqual(policy.evaluate([resourceUsage(cpu: 600)], now: 65).notify.count, 1)
    }

}
