import XCTest
@testable import cleanMac

final class ScanDiagnosticsTests: XCTestCase {
    func testMissingOptionalPathIsNotReportedAsFailure() {
        let collector = ScanDiagnosticsCollector()
        collector.failure("/missing", error: NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError))
        let report = collector.snapshot(finished: true)
        XCTAssertEqual(report.status, .complete)
        XCTAssertEqual(report.missingCount, 1)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testPermissionDeniedProducesPartialResult() {
        let collector = ScanDiagnosticsCollector()
        collector.failure("/protected", error: NSError(domain: NSPOSIXErrorDomain, code: 13))
        collector.failure("/protected", error: NSError(domain: NSPOSIXErrorDomain, code: 13))
        let report = collector.snapshot(finished: true)
        XCTAssertEqual(report.status, .partial)
        XCTAssertEqual(report.issues.count, 1)
        XCTAssertEqual(report.issues.first?.permissionDenied, true)
        XCTAssertNotNil(report.summary)
    }

    func testCancellationCannotBecomeACompleteResult() {
        let collector = ScanDiagnosticsCollector()
        collector.visit("/file")
        collector.skip("/ignored")
        let report = collector.snapshot(finished: true, cancelled: true)
        XCTAssertEqual(report.status, .cancelled)
        XCTAssertEqual(report.skippedCount, 1)
        XCTAssertNotNil(report.summary)
    }

    func testDiagnosticJSONRetainsStatusAndIssuePath() throws {
        let collector = ScanDiagnosticsCollector()
        collector.failure("/unreadable", error: NSError(domain: NSPOSIXErrorDomain, code: 1))
        let data = try JSONEncoder().encode(collector.snapshot(finished: true))
        let report = try JSONDecoder().decode(ScanDiagnostics.self, from: data)
        XCTAssertEqual(report.status, .partial)
        XCTAssertEqual(report.issues.first?.path, "/unreadable")
    }

    func testTaskContextSurvivesDetachedScanAndCancellation() async {
        let collector = ScanDiagnosticsCollector()
        let task = Task {
            await ScanContext.$diagnostics.withValue(collector) {
                await ScanTask.run {
                    ScanContext.diagnostics?.visit("/started")
                    while !Task.isCancelled { Thread.sleep(forTimeInterval: 0.001) }
                    return Task.isCancelled
                }
            }
        }
        try? await Task.sleep(for: .milliseconds(30))
        task.cancel()
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
        XCTAssertEqual(collector.snapshot().currentPath, "/started")
    }

    func testDirectorySizeStillReadsFilesAndSkipsSymbolicLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 37).write(to: root.appendingPathComponent("nested/file.bin"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root)
        XCTAssertEqual(FileHelper.directorySize(root.path), 37)
    }
}
