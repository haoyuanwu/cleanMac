import SwiftUI
import AppKit

private final class CleanMacAppDelegate: NSObject, NSApplicationDelegate {
    private var finishedLaunching = false
    private var startedApplicationInventory = false
    private var startupScanTask: Task<Void, Never>?
    private var startupWindowObserver: NSObjectProtocol?

    // 红色关闭按钮只关闭主窗口；状态栏、监测与计划任务继续运行。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // 从 Finder 再次打开运行中的应用时，恢复主窗口和 Dock 图标。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 已有窗口时交给 AppKit 恢复焦点，避免重复强制激活干扰系统确认窗口。
        if flag { return true }
        AppActionCoordinator.shared.requestMainWindow()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        StorageGrowthMonitor.shared.start()
        TrashMonitor.shared.start()
        DeviceStatusMonitor.shared.start()
        NetworkSpeedMonitor.shared.start()
        DeviceMemoryMonitor.shared.start()
        BatteryAlertMonitor.shared.start()
        ScheduledScanService.shared.start()
        NetworkSpeedStatusItem.shared.start()
        ResourceAlertPresenter.shared.start()
        finishedLaunching = true
        startupWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleApplicationInventory() }
        }
        scheduleApplicationInventory()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        scheduleApplicationInventory()
    }

    private func scheduleApplicationInventory() {
        guard finishedLaunching, !startedApplicationInventory, startupScanTask == nil,
              AppActionCoordinator.shared.isMainWindowReadyForBackgroundScan else { return }
        startupScanTask = Task(priority: .utility) { [weak self] in
            defer { self?.startupScanTask = nil }
            // 首帧和系统确认先完成，失去前台焦点时等待下次就绪事件。
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, AppActionCoordinator.shared.isMainWindowReadyForBackgroundScan else { return }
            self.startedApplicationInventory = true
            if let observer = self.startupWindowObserver {
                NotificationCenter.default.removeObserver(observer)
                self.startupWindowObserver = nil
            }
            await MainViewModel.shared.scanApplicationsOnStartup()
        }
    }
}

/// 捕获主场景的 openWindow 动作，供原生状态栏在主窗口关闭后重新打开。
private struct MainWindowRequestRouter: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear {
                AppActionCoordinator.shared.registerWindowOpener { openWindow(id: "main") }
            }
    }
}

private struct MainWindowTracker: NSViewRepresentable {
    func makeNSView(context: Context) -> TrackingView { TrackingView() }
    func updateNSView(_ nsView: TrackingView, context: Context) {}

    final class TrackingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                AppActionCoordinator.shared.registerMainWindow(window)
            }
        }
    }
}

@main
struct cleanMacApp: App {
    @NSApplicationDelegateAdaptor(CleanMacAppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("cleanMac", id: "main") {
            ContentView()
                .background(MainWindowTracker())
                .background(MainWindowRequestRouter())
        }
        .windowToolbarStyle(.unifiedCompact)
        .windowStyle(.hiddenTitleBar)

        // 菜单栏命令
        .commands {
            CommandGroup(after: .newItem) {
                Button("清理扫描") {
                    NotificationCenter.default.post(name: .init("scanAll"), object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}
