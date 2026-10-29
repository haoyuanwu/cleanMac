import XCTest
@testable import cleanMac

final class ApplicationCacheScannerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    private func write(_ relativePath: String, size: Int = 12) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: size).write(to: url)
        return url
    }

    private var application: CacheApplication {
        CacheApplication(id: "com.example.Editor", name: "Editor", path: "/Applications/Editor.app")
    }

    private var installed: [ApplicationCacheScanner.InstalledApplication] {
        [.init(application: application, aliases: ["editor", "com.example.editor"])]
    }

    func testDiscoversNestedApplicationsWithoutEmbeddedHelpers() throws {
        let app = temporaryDirectory.appendingPathComponent("Applications/Vendor/Editor.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "com.example.Editor", "CFBundleName": "Editor"]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        let helper = app.appendingPathComponent("Contents/Helpers/Helper.app/Contents")
        try FileManager.default.createDirectory(at: helper, withIntermediateDirectories: true)
        try data.write(to: helper.appendingPathComponent("Info.plist"))
        let found = ApplicationCacheScanner.installedApplications(
            searchPaths: [temporaryDirectory.appendingPathComponent("Applications").path]
        )
        XCTAssertEqual(found.count, 1)
        let foundPath = found.first.map { URL(fileURLWithPath: $0.application.path!).resolvingSymlinksInPath().path }
        XCTAssertEqual(foundPath, app.resolvingSymlinksInPath().path)
    }

    func testOwnershipUsesUnambiguousNamesAndBundleBoundaries() {
        XCTAssertEqual(ApplicationCacheScanner.owner(of: "com.example.Editor.helper", applications: installed), application)
        XCTAssertEqual(ApplicationCacheScanner.owner(of: "TEAM.com.example.Editor", applications: installed), application)
        XCTAssertNil(ApplicationCacheScanner.owner(of: "com.example.EditorOther", applications: installed))
        let collision = ApplicationCacheScanner.InstalledApplication(
            application: CacheApplication(id: "com.other.Editor", name: "Editor", path: nil), aliases: ["editor"]
        )
        XCTAssertNil(ApplicationCacheScanner.owner(of: "Editor", applications: installed + [collision]))
    }

    func testCacheDiscoverySkipsDataPackagesSymlinksAndNestedDuplicates() throws {
        let root = temporaryDirectory.appendingPathComponent("Support/Editor")
        let cache = try write("Support/Editor/Profile/Code Cache/data.bin", size: 20)
        _ = try write("Support/Editor/Profile/Code Cache/GPUCache/data.bin", size: 30)
        let file = try write("Support/Editor/Profile/cache.db", size: 7)
        _ = try write("Support/Editor/Profile/settings.json")
        _ = try write("Support/Editor/Profile/initial-rendering-cache-config.json")
        _ = try write("Support/Editor/Documents/Cache/note.txt")
        _ = try write("Support/Editor/Resource.app/Contents/Cache/data.bin")
        let outside = try write("outside/Cache/secret.txt")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("LinkedCache"),
                                                 withDestinationURL: outside.deletingLastPathComponent())
        let roots = [ApplicationCacheScanner.DataRoot(url: root, owner: application, isCacheRoot: false)]
        let items = ApplicationCacheScanner.cacheItems(in: roots)
        XCTAssertEqual(Set(items.map(\.path)), [cache.deletingLastPathComponent().path, file.path])
        XCTAssertEqual(items.reduce(0) { $0 + $1.size }, 57)
        XCTAssertTrue(items.allSatisfy { $0.cacheApplication == application })
        XCTAssertTrue(items.contains { !$0.isDirectory })
    }

    func testDataRootsMatchVendorPathsAndAvoidParentChildOverlap() throws {
        _ = try write("Home/Library/Caches/Vendor/Editor/cache.bin")
        _ = try write("Home/Library/Application Support/Editor/GPUCache/data.bin")
        _ = try write("Home/Library/Containers/com.example.Editor/Data/Library/Caches/data.bin")
        _ = try write("Home/Library/Application Support/Unrelated/Cache/data.bin")
        let roots = ApplicationCacheScanner.dataRoots(
            applications: installed, home: temporaryDirectory.appendingPathComponent("Home"),
            sharedLibrary: temporaryDirectory.appendingPathComponent("SharedLibrary")
        )
        XCTAssertEqual(roots.count, 3)
        let cacheRoot = try XCTUnwrap(roots.first(where: \.isCacheRoot))
        let overlapping = ApplicationCacheScanner.DataRoot(url: cacheRoot.url.appendingPathComponent("Nested"),
                                                          owner: application, isCacheRoot: false)
        let items = ApplicationCacheScanner.cacheItems(in: roots + [cacheRoot, overlapping])
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Set(items.map(\.path)).count, items.count)
    }

    func testNonstandardCachesRequireExplicitSelection() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(SafetyWhitelist.riskLevel(for: home + "/Library/Caches/com.example.Editor", category: .applicationCache), .safe)
        XCTAssertEqual(SafetyWhitelist.riskLevel(for: home + "/Library/Application Support/Editor/Code Cache", category: .applicationCache), .caution)
        XCTAssertEqual(SafetyWhitelist.riskLevel(for: "/Library/Caches/com.example.Editor", category: .applicationCache), .sensitive)
    }

    func testSandboxUserDirectoryLinksDoNotHideLibraryCaches() throws {
        let root = temporaryDirectory.appendingPathComponent("Home/Library/Containers/com.example.Editor")
        let data = root.appendingPathComponent("Data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        // 模拟 macOS 沙盒：用户目录符号链接与真正的 Library 目录并列。
        try FileManager.default.createSymbolicLink(at: data.appendingPathComponent("Desktop"),
                                                 withDestinationURL: temporaryDirectory)
        let libraryCache = try write("Home/Library/Containers/com.example.Editor/Data/Library/Caches/cache.bin", size: 23)
        let privateCache = try write("Home/Library/Containers/com.example.Editor/Data/Documents/app_data/web/GPUCache/data.bin", size: 41)
        _ = try write("Home/Library/Containers/com.example.Editor/Data/Documents/messages/chat.db", size: 90)
        _ = try write("Home/Library/Containers/com.example.Editor/Data/Documents/attachments/photo.jpg", size: 80)
        let roots = ApplicationCacheScanner.dataRoots(
            applications: installed, home: temporaryDirectory.appendingPathComponent("Home"),
            sharedLibrary: temporaryDirectory.appendingPathComponent("SharedLibrary")
        )
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots.first?.isSandboxContainer, true)
        let items = ApplicationCacheScanner.cacheItems(in: roots)
        XCTAssertEqual(Set(items.map(\.path)), [libraryCache.deletingLastPathComponent().path, privateCache.deletingLastPathComponent().path])
        XCTAssertEqual(items.reduce(0) { $0 + $1.size }, 64)
    }

    func testContainerMetadataResolvesIdentifierNamedByUUID() throws {
        let container = temporaryDirectory.appendingPathComponent("Home/Library/Containers/01234567-89AB-CDEF")
        let cache = try write("Home/Library/Containers/01234567-89AB-CDEF/Data/Library/Caches/data.bin")
        let metadata = try PropertyListSerialization.data(
            fromPropertyList: ["MCMMetadataIdentifier": "com.example.Editor"], format: .binary, options: 0
        )
        try metadata.write(to: container.appendingPathComponent(".com.apple.containermanagerd.metadata.plist"))
        let roots = ApplicationCacheScanner.dataRoots(
            applications: installed, home: temporaryDirectory.appendingPathComponent("Home"),
            sharedLibrary: temporaryDirectory.appendingPathComponent("SharedLibrary")
        )
        XCTAssertEqual(roots.first?.owner, application)
        XCTAssertEqual(ApplicationCacheScanner.cacheItems(in: roots).first?.path, cache.deletingLastPathComponent().path)
    }

    func testAllContainersAreScannedWithoutAnInstalledApplicationMatch() throws {
        let first = try write("Home/Library/Containers/org.example.Missing/Data/Library/Caches/data.bin")
        let second = try write("Home/Library/Containers/Other App/Data/Documents/app_data/Code Cache/data.bin")
        let group = try write("Home/Library/Group Containers/TEAM.org.example.Missing/Documents/Cache/data.bin")
        _ = try write("Home/Library/Application Support/Unrelated/Cache/data.bin")
        let roots = ApplicationCacheScanner.dataRoots(
            applications: [], home: temporaryDirectory.appendingPathComponent("Home"),
            sharedLibrary: temporaryDirectory.appendingPathComponent("SharedLibrary")
        )
        XCTAssertEqual(roots.count, 3)
        XCTAssertTrue(roots.allSatisfy(\.isSandboxContainer))
        let items = ApplicationCacheScanner.cacheItems(in: roots)
        XCTAssertEqual(Set(items.map(\.path)), Set([first, second, group].map { $0.deletingLastPathComponent().path }))
        XCTAssertTrue(items.allSatisfy { $0.cacheApplication != nil })
        XCTAssertTrue(items.contains { $0.cacheApplication?.name == "Other App" })
    }

    func testContainerIdentifierEndingInAppIsNotMistakenForApplicationResources() throws {
        let cache = try write("Home/Library/Containers/com.example.app/Data/Library/Caches/data.bin")
        let roots = ApplicationCacheScanner.dataRoots(applications: [], home: temporaryDirectory.appendingPathComponent("Home"),
                                                      sharedLibrary: temporaryDirectory.appendingPathComponent("SharedLibrary"))
        XCTAssertEqual(roots.count, 1)
        XCTAssertEqual(roots.first?.kind, .container)
        XCTAssertEqual(ApplicationCacheScanner.cacheItems(in: roots).first?.path, cache.deletingLastPathComponent().path)
    }

    func testEmptyRootsPersistExpireAndRescanWhenChanged() throws {
        let suite = "cleanMac.ignore-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CacheScanIgnoreStore(defaults: defaults)
        let file = try write("Support/Empty/settings.json")
        let root = file.deletingLastPathComponent()
        let roots = [ApplicationCacheScanner.DataRoot(url: root, owner: application, isCacheRoot: false)]
        let now = Date()
        XCTAssertTrue(ApplicationCacheScanner.cacheItems(in: roots, ignoreStore: store, now: now).isEmpty)
        XCTAssertEqual(store.allRecords.count, 1)
        XCTAssertTrue(store.shouldSkip(root.path, at: now.addingTimeInterval(60)))
        XCTAssertTrue(CacheScanIgnoreStore(defaults: defaults).shouldSkip(root.path, at: now.addingTimeInterval(60)))
        XCTAssertFalse(store.shouldSkip(root.path, at: now.addingTimeInterval(CacheScanIgnoreStore.lifetime)))
        _ = try write("Support/Empty/GPUCache/data.bin")
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(2)], ofItemAtPath: root.path)
        XCTAssertFalse(store.shouldSkip(root.path, at: now.addingTimeInterval(3)))
        XCTAssertEqual(ApplicationCacheScanner.cacheItems(in: roots, ignoreStore: store, now: now.addingTimeInterval(3)).count, 1)
        XCTAssertTrue(store.allRecords.isEmpty)
    }

    func testEmptyCacheRootsCanBeIgnoredButMissingRootsCannot() throws {
        let suite = "cleanMac.ignore-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CacheScanIgnoreStore(defaults: defaults)
        let root = temporaryDirectory.appendingPathComponent("Support/EmptyCache")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Cache"), withIntermediateDirectories: true)
        let roots = [root, temporaryDirectory.appendingPathComponent("Missing")].map {
            ApplicationCacheScanner.DataRoot(url: $0, owner: application, isCacheRoot: false)
        }
        let now = Date()
        XCTAssertTrue(ApplicationCacheScanner.cacheItems(in: roots, ignoreStore: store, now: now).isEmpty)
        XCTAssertEqual(store.allRecords.map(\.path), [root.path])
        _ = try write("Support/EmptyCache/Cache/new.bin")
        let later = now.addingTimeInterval(CacheScanIgnoreStore.lifetime + 1)
        XCTAssertEqual(ApplicationCacheScanner.cacheItems(in: roots, ignoreStore: store, now: later).count, 1)
        XCTAssertTrue(store.allRecords.isEmpty)
    }

    func testRestoringPathsRejectsStaleScanUpdates() throws {
        let suite = "cleanMac.ignore-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CacheScanIgnoreStore(defaults: defaults)
        let file = try write("Support/Empty/settings.json")
        let record = try XCTUnwrap(CacheScanIgnoreStore.record(for: file.deletingLastPathComponent().path,
                                                             applicationName: "Editor", at: Date()))
        let revision = store.revision
        store.apply(emptyRoots: [record], rescannedPaths: [record.path], expectedRevision: revision)
        store.remove(record.path)
        store.apply(emptyRoots: [record], rescannedPaths: [record.path], expectedRevision: revision)
        XCTAssertTrue(store.allRecords.isEmpty)
        store.apply(emptyRoots: [record], rescannedPaths: [record.path], expectedRevision: store.revision)
        store.removeAll()
        XCTAssertTrue(CacheScanIgnoreStore(defaults: defaults).allRecords.isEmpty)
    }
}
