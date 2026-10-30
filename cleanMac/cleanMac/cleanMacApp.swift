import SwiftUI
import AppKit

private final class CleanMacAppDelegate: NSObject, NSApplicationDelegate {
    // 红色关闭按钮只关闭主窗口；状态栏、监测与计划任务继续运行。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // 从 Finder 再次打开运行中的应用时，恢复主窗口和 Dock 图标。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
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
