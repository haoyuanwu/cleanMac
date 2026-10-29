import XCTest
@testable import cleanMac

final class AppUninstallAssociationTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var app: URL!
    private var systemLibrary: URL!
    private let identifier = "com.vendor.Editor"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        home = root.appendingPathComponent("Home")
        systemLibrary = root.appendingPathComponent("SharedLibrary")
        app = root.appendingPathComponent("Applications/Editor.app")
        try plist(["CFBundleIdentifier": identifier, "CFBundleName": "Editor"], at: app.appendingPathComponent("Contents/Info.plist"))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private var installed: [ApplicationCacheScanner.InstalledApplication] {
        [.init(application: .init(id: identifier, name: "Editor", path: app.path), aliases: ["editor", identifier.lowercased()])]
    }
    private func plist(_ dictionary: [String: Any], at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0).write(to: url)
    }
    @discardableResult private func write(_ relative: String) throws -> URL {
        let url = home.appendingPathComponent("Library/" + relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: url)
        return url
    }
    private func inspect(groups: Set<String> = [], claims: [String: Set<String>] = [:]) -> AppLeftoverEstimate {
        AppLeftoverScanner.inspect(appPath: app.path, applications: installed, home: home,
                                   systemLibrary: systemLibrary, declaredGroups: groups, groupClaims: claims)
    }

    func testExactIdentityExplainsOwnershipAndPreservesUserDataByDefault() throws {
        let cache = try write("Caches/\(identifier)/data")
        let preferences = try write("Preferences/\(identifier).plist")
        let state = try write("Saved Application State/\(identifier).savedState/data")
        let support = try write("Application Support/\(identifier)/document")
        let items = inspect().leftovers
        XCTAssertTrue(try XCTUnwrap(items.first { $0.path == cache.deletingLastPathComponent().path }).defaultSelected)
        XCTAssertTrue(try XCTUnwrap(items.first { $0.path == state.deletingLastPathComponent().path }).defaultSelected)
        XCTAssertFalse(try XCTUnwrap(items.first { $0.path == preferences.path }).defaultSelected)
        XCTAssertFalse(try XCTUnwrap(items.first { $0.path == support.deletingLastPathComponent().path }).defaultSelected)
        XCTAssertTrue(items.allSatisfy { !$0.ownershipReason.isEmpty && !$0.impact.isEmpty })
    }
    func testUUIDContainerUsesMetadataAndRejectsConflictingNameMetadata() throws {
        let good = try write("Containers/UUID-A/Data/Library/Caches/data")
        try plist(["MCMMetadataIdentifier": identifier], at: home.appendingPathComponent("Library/Containers/UUID-A/.com.apple.containermanagerd.metadata.plist"))
        _ = try write("Containers/\(identifier)/Data/document")
        try plist(["MCMMetadataIdentifier": "com.other.Editor"], at: home.appendingPathComponent("Library/Containers/\(identifier)/.com.apple.containermanagerd.metadata.plist"))
        let containers = inspect().leftovers.filter { $0.categoryLabel == "沙盒容器" }
        XCTAssertEqual(containers.count, 1)
        XCTAssertTrue(good.path.hasPrefix(containers[0].path + "/"))
        XCTAssertFalse(containers[0].defaultSelected)
    }
    func testDeclaredGroupHasKnownConsumersAndIsNeverPreselected() throws {
        let group = "TEAM.com.vendor.shared"
        _ = try write("Group Containers/\(group)/database")
        _ = try write("Group Containers/TEAM.com.vendor.other/database")
        let groups = inspect(groups: [group], claims: [identifier: [group], "com.vendor.Reader": [group]]).leftovers.filter { $0.categoryLabel == "共享容器" }
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].isShared)
        XCTAssertTrue(groups[0].isSelectable)
        XCTAssertFalse(groups[0].defaultSelected)
        XCTAssertEqual(groups[0].relatedBundleIdentifiers, [identifier, "com.vendor.Reader"])
    }
    func testGroupContainerWithUUIDUsesMetadata() throws {
        let group = "TEAM.com.vendor.shared"
        _ = try write("Group Containers/GROUP-UUID/data")
        try plist(["MCMMetadataIdentifier": group], at: home.appendingPathComponent("Library/Group Containers/GROUP-UUID/.com.apple.containermanagerd.metadata.plist"))
        XCTAssertEqual(inspect(groups: [group]).leftovers.filter { $0.categoryLabel == "共享容器" }.count, 1)
    }
    func testNameOnlyCandidateIsReadOnlyAndNotPreselected() throws {
        _ = try write("Application Support/Editor/document")
        let item = try XCTUnwrap(inspect().leftovers.first { $0.name == "Editor" })
        XCTAssertTrue(item.isShared)
        XCTAssertFalse(item.defaultSelected)
        XCTAssertFalse(item.isSelectable)
        XCTAssertFalse(AppLeftoverScanner.canRemove(item))
    }
    func testDeclaredApplicationNameFindsDifferentDataDirectoryName() throws {
        try plist(["CFBundleIdentifier": identifier, "CFBundleName": "Code"], at: app.appendingPathComponent("Contents/Info.plist"))
        _ = try write("Application Support/Code/settings.json")
        let item = try XCTUnwrap(inspect().leftovers.first { $0.name == "Code" })
        XCTAssertFalse(item.defaultSelected)
        XCTAssertFalse(item.isSelectable)
        XCTAssertFalse(item.sizeIsKnown)
    }

    func testVendorDirectoryIsReadOnlySharedHint() throws {
        _ = try write("Application Support/Vendor/Reader/document")
        let item = try XCTUnwrap(inspect().leftovers.first { $0.name == "Vendor" })
        XCTAssertTrue(item.isShared)
        XCTAssertFalse(item.isSelectable)
        XCTAssertFalse(item.defaultSelected)
    }
    func testLaunchItemsRequireExecutableBoundaryOrIdentifierAndRemainReadOnly() throws {
        let base = home.appendingPathComponent("Library/LaunchAgents")
        try plist(["Label": "helper.custom", "ProgramArguments": [app.appendingPathComponent("Contents/MacOS/helper").path]], at: base.appendingPathComponent("owned.plist"))
        try plist(["Label": identifier + ".helper", "Program": "/bin/true"], at: base.appendingPathComponent("label.plist"))
        try plist(["Label": "unrelated", "Program": app.path + "Other/Contents/helper"], at: base.appendingPathComponent("unrelated.plist"))
        try plist(["Label": identifier, "Program": "/bin/true"], at: systemLibrary.appendingPathComponent("LaunchDaemons/system.plist"))
        let inspected = inspect()
        XCTAssertEqual(inspected.bundleIdentifier, identifier)
        let launch = inspected.leftovers.filter { $0.categoryLabel == "启动项 · 只读" }
        XCTAssertEqual(launch.count, 3, "items=\(inspected.leftovers.map { ($0.path, $0.categoryLabel) }), issues=\(inspected.issues)")
        XCTAssertTrue(launch.allSatisfy { !$0.isSelectable && !$0.defaultSelected && !AppLeftoverScanner.canRemove($0) })
    }
    func testByHostPreferenceRequiresExactBundleAndUUID() throws {
        let uuid = UUID().uuidString
        _ = try write("Preferences/ByHost/\(identifier).\(uuid).plist")
        _ = try write("Preferences/ByHost/\(identifier).Other.\(uuid).plist")
        let byHost = inspect().leftovers.filter { $0.path.contains("/ByHost/") }
        XCTAssertEqual(byHost.count, 1)
        XCTAssertTrue(byHost[0].name.hasSuffix(uuid + ".plist"))
    }
    func testSymlinkCandidateCannotEscapeLibrary() throws {
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: outside.appendingPathComponent("data"))
        let cache = home.appendingPathComponent("Library/Caches")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent(identifier), withDestinationURL: outside)
        XCTAssertFalse(inspect().leftovers.contains { $0.path == cache.appendingPathComponent(identifier).path })
        XCTAssertEqual(try String(contentsOf: outside.appendingPathComponent("data"), encoding: .utf8), "keep")
    }
    func testChangedDirectoryIdentityFailsRevalidation() throws {
        _ = try write("Caches/\(identifier)/data")
        let item = try XCTUnwrap(inspect().leftovers.first { $0.categoryLabel == "缓存" })
        XCTAssertTrue(AppLeftoverScanner.canRemove(item))
        try FileManager.default.moveItem(atPath: item.path, toPath: item.path + "-old")
        try FileManager.default.createDirectory(atPath: item.path, withIntermediateDirectories: true)
        XCTAssertFalse(AppLeftoverScanner.canRemove(item))
    }
    func testCrossApplicationDuplicateBecomesSharedAndCountsOnce() throws {
        _ = try write("Caches/\(identifier)/data")
        let estimate = inspect()
        var other = estimate
        other = AppLeftoverEstimate(appPath: "/other.app", appName: "Other", bundleIdentifier: "com.vendor.Other", appSize: 0, leftovers: estimate.leftovers)
        let merged = AppLeftoverSelection.merged([estimate, other])
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].isShared)
        XCTAssertFalse(merged[0].defaultSelected)
    }
    func testParentChildSelectionCountsOnce() {
        let parent = AppLeftoverItem(id: "/Library/A", path: "/Library/A", name: "A", size: 100, isDirectory: true)
        let child = AppLeftoverItem(id: "/Library/A/B", path: "/Library/A/B", name: "B", size: 20, isDirectory: true)
        let sibling = AppLeftoverItem(id: "/Library/A-other", path: "/Library/A-other", name: "A-other", size: 10, isDirectory: false)
        XCTAssertEqual(AppLeftoverSelection.coveredOnce([child, sibling, parent, parent]).reduce(0) { $0 + $1.size }, 110)
    }
    func testInvalidBundleIdentifierDoesNotEscapeIntoOtherDirectories() throws {
        try plist(["CFBundleIdentifier": "../../outside"], at: app.appendingPathComponent("Contents/Info.plist"))
        let result = inspect()
        XCTAssertNil(result.bundleIdentifier)
        XCTAssertFalse(result.issues.isEmpty)
        XCTAssertTrue(result.leftovers.allSatisfy { !$0.isSelectable })
    }
    func testUninstallPreflightProtectsSystemSelfAndEmbeddedHelpers() throws {
        let applicationRoot = root.appendingPathComponent("Applications").path
        XCTAssertTrue(ApplicationUninstallPreflight.canUninstall(app.path, roots: [applicationRoot], currentAppPath: "/other.app"))
        XCTAssertFalse(ApplicationUninstallPreflight.canUninstall(app.path, roots: [applicationRoot], currentAppPath: app.path))
        let nested = app.appendingPathComponent("Contents/Helpers/Nested.app")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertFalse(ApplicationUninstallPreflight.canUninstall(nested.path, roots: [applicationRoot], currentAppPath: "/other.app"))
        let system = root.appendingPathComponent("Applications/Safari.app")
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        XCTAssertFalse(ApplicationUninstallPreflight.canUninstall(system.path, roots: [applicationRoot], currentAppPath: "/other.app"))
    }
    func testRunningHelpersMatchAppBoundaryAndRelatedBundleIdentifiers() {
        let helper = RunningUninstallApplication(pid: 1, name: "Helper", bundleIdentifier: "helper", bundlePath: nil, executablePath: app.path + "/Contents/helper")
        let neighbor = RunningUninstallApplication(pid: 2, name: "Neighbor", bundleIdentifier: "other", bundlePath: app.path + "Other", executablePath: nil)
        XCTAssertTrue(ApplicationUninstallPreflight.matches(helper, appPaths: [app.path], bundleIdentifiers: []))
        XCTAssertFalse(ApplicationUninstallPreflight.matches(neighbor, appPaths: [app.path], bundleIdentifiers: []))
        XCTAssertTrue(ApplicationUninstallPreflight.matches(neighbor, appPaths: [], bundleIdentifiers: ["other"]))
    }
    func testDirectoryWithoutReadableSigningMetadataHasNoInferredAppGroups() {
        XCTAssertTrue(AppLeftoverScanner.groupIdentifiers(at: app.path).isEmpty)
    }
}
