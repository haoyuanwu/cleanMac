import SwiftUI

/// 详情页和状态栏直接发起整理，共享运行状态和结果。
struct MemoryMaintenanceButton: View {
    var compact = false
    @State private var showingResult = false
    @ObservedObject private var helper = MemoryHelperController.shared
    @ObservedObject private var service = MemoryMaintenanceService.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if service.running && !compact { ProgressView().controlSize(.small) }
                Button(service.running ? (compact ? "整理中…" : "正在整理…") : "整理内存") {
                    service.run()
                }.buttonStyle(ReadableControlButtonStyle()).controlSize(.small).disabled(service.running)
                    .help("整理系统可回收缓存；首次需要批准辅助服务，之后无需逐次授权。")
                if compact, let message = service.message {
                    Button { showingResult.toggle() } label: {
                        Image(systemName: "info.circle").foregroundStyle(Theme.actionInk)
                    }.buttonStyle(.plain).help(message).accessibilityLabel("查看整理结果")
                        .popover(isPresented: $showingResult) {
                            Text(message).font(.system(size: 12)).textSelection(.enabled).padding(16).frame(width: 280)
                        }
                }
            }
            if !compact {
                HStack {
                    Text(helper.statusText).font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
                    Spacer()
                    Menu("辅助服务") {
                        Button("申请授权") { service.requestHelperAuthorization() }
                        Button("前往系统授权设置", action: helper.openSettings)
                        Button("移除后台服务", role: .destructive) { service.removeHelper() }
                    }.disabled(service.running)
                }
            }
            if !compact, let message = service.message {
                Text(message).font(.system(size: 11)).foregroundStyle(Theme.navigationSecondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
        }.onAppear { helper.refreshStatus() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in helper.refreshStatus() }
    }
}
