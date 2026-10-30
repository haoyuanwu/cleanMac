import Combine
import AppKit

/// 在菜单栏窗口和主窗口之间传递一次性操作请求。
@MainActor
final class AppActionCoordinator: ObservableObject {
    static let shared = AppActionCoordinator()

    @Published private(set) var overviewScanRequest = 0
    @Published private(set) var deepScanRequest = 0
    @Published private(set) var deviceInfoRequest = 0
    @Published private(set) var trashReviewRequest = 0
    @Published private(set) var mainWindowRequest = 0
    private var hasPendingOverviewScan = false
    private var hasPendingDeepScan = false
    private var hasPendingDeviceInfo = false
    private var hasPendingTrashReview = false
    private var hasPendingMainWindow = false
    private weak var mainWindow: NSWindow?
    private var mainWindowCloseObserver: NSObjectProtocol?
    private var windowOpener: (() -> Void)?

    private init() {}

    func registerMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        if let mainWindowCloseObserver {
            NotificationCenter.default.removeObserver(mainWindowCloseObserver)
        }
        mainWindow = window
        NSApp.setActivationPolicy(.regular)
        let closingWindowID = ObjectIdentifier(window)
        mainWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // 在主窗口关闭的同一轮事件中隐藏 Dock，避免异步切换时与重新打开竞争。
            MainActor.assumeIsolated {
                guard let self else { return }
                if let mainWindow = self.mainWindow,
                   ObjectIdentifier(mainWindow) != closingWindowID { return }
                self.mainWindow = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func showMainWindow(openWindow: () -> Void) {
        NSApp.setActivationPolicy(.regular)
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

    func requestDeepScan() {
        hasPendingDeepScan = true
        deepScanRequest += 1
    }

    func consumeDeepScanRequest() -> Bool {
        guard hasPendingDeepScan else { return false }
        hasPendingDeepScan = false
        return true
    }

    func requestDeviceInfo() {
        hasPendingDeviceInfo = true
        deviceInfoRequest += 1
    }

    func consumeDeviceInfoRequest() -> Bool {
        guard hasPendingDeviceInfo else { return false }
        hasPendingDeviceInfo = false
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

    func registerWindowOpener(_ opener: @escaping () -> Void) {
        windowOpener = opener
        if consumeMainWindowRequest() { showMainWindow(openWindow: opener) }
    }

    func requestMainWindow() {
        hasPendingMainWindow = true
        mainWindowRequest += 1
        if let windowOpener, consumeMainWindowRequest() { showMainWindow(openWindow: windowOpener) }
    }

    func consumeMainWindowRequest() -> Bool {
        guard hasPendingMainWindow else { return false }
        hasPendingMainWindow = false
        return true
    }
}
