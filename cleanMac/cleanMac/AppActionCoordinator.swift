import Combine
import AppKit

/// 在菜单栏窗口和主窗口之间传递一次性操作请求。
@MainActor
final class AppActionCoordinator: ObservableObject {
    static let shared = AppActionCoordinator()

    @Published private(set) var overviewScanRequest = 0
    @Published private(set) var trashReviewRequest = 0
    @Published private(set) var mainWindowRequest = 0
    private var hasPendingOverviewScan = false
    private var hasPendingTrashReview = false
    private var hasPendingMainWindow = false
    private weak var mainWindow: NSWindow?

    private init() {}

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
    }

    func showMainWindow(openWindow: () -> Void) {
        if let mainWindow {
            mainWindow.deminiaturize(nil)
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            openWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func requestOverviewScan() {
        hasPendingOverviewScan = true
        overviewScanRequest += 1
    }

    func consumeOverviewScanRequest() -> Bool {
        guard hasPendingOverviewScan else { return false }
        hasPendingOverviewScan = false
        return true
    }

    func requestTrashReview() {
        hasPendingTrashReview = true
        trashReviewRequest += 1
    }

    func consumeTrashReviewRequest() -> Bool {
        guard hasPendingTrashReview else { return false }
        hasPendingTrashReview = false
        return true
    }

    func requestMainWindow() {
        hasPendingMainWindow = true
        mainWindowRequest += 1
    }

    func consumeMainWindowRequest() -> Bool {
        guard hasPendingMainWindow else { return false }
        hasPendingMainWindow = false
        return true
    }
}
