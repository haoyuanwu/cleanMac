import SwiftUI

@main
struct cleanMacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        // 菜单栏命令
        .commands {
            CommandGroup(after: .newItem) {
                Button("全盘扫描") {
                    NotificationCenter.default.post(name: .init("scanAll"), object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}
