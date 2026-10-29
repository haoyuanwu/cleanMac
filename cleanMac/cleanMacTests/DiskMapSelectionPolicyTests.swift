import XCTest
@testable import cleanMac

final class DiskMapSelectionPolicyTests: XCTestCase {
    func testSystemAndFoundationPathsAreProtected() {
        for path in ["/", "/System/Library/Caches/item", "/usr/local/bin/tool", "/private/var/db", "/Users", "/Applications", "/Library", "/Library/Preferences/example.plist"] {
            XCTAssertNotNil(DiskMapSelectionPolicy.protectionReason(for: path), path)
        }
    }

    func testUserRootsAndAppResourcesAreProtectedButIndividualFilesRemainSelectable() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for path in [home, home + "/Documents", home + "/Downloads", home + "/Library/Containers/app", "/Applications/Example.app/Contents/Resources/icon.png"] {
            XCTAssertNotNil(DiskMapSelectionPolicy.protectionReason(for: path), path)
        }
        for path in [home + "/Downloads/archive.zip", home + "/Documents/project", home + "/Library/Caches/com.example.app"] {
            XCTAssertNil(DiskMapSelectionPolicy.protectionReason(for: path), path)
        }
    }

    func testSymbolicLinkCannotBypassSystemProtection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appendingPathComponent("system-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/System"))
        XCTAssertNotNil(DiskMapSelectionPolicy.protectionReason(for: link.path))
    }
}
