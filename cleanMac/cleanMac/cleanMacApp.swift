import SwiftUI
import AppKit

private final class CleanMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        StorageGrowthMonitor.shared.start()
        TrashMonitor.shared.start()
        ScheduledScanService.shared.start()
    }
}

private struct MenuBarWindowRouter: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var appActions = AppActionCoordinator.shared

    var body: some View {
        Image(systemName: "internaldrive.fill")
            .task { openPendingWindow() }
            .onChange(of: appActions.mainWindowRequest) { _ in openPendingWindow() }
    }

    private func openPendingWindow() {
        guard appActions.consumeMainWindowRequest() else { return }
        appActions.showMainWindow { openWindow(id: "main") }
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
        }
        .windowToolbarStyle(.unifiedCompact)
        .windowStyle(.hiddenTitleBar)

        // 菜单栏迷你仪表
        MenuBarExtra {
            MenuBarStatusView()
        } label: {
            MenuBarWindowRouter()
        }
        .menuBarExtraStyle(.window)

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
