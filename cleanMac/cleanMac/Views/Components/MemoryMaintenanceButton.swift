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
                Button { service.run() } label: {
                    if compact {
                        PopupOperationLabel(title: "整理内存", runningTitle: "整理中…", symbol: "sparkles",
                                            running: service.running)
                    } else {
                        Text(service.running ? "正在整理…" : "整理内存")
                    }
                }.buttonStyle(ReadableControlButtonStyle(tint: .purple, compact: compact, inProgress: compact && service.running))
                    .disabled(service.running)
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

/// 状态栏操作共用内容尺寸、状态动画和按钮内进度，避免加载时移动卡片标题。
struct PopupOperationLabel: View {
    let title: String
    let runningTitle: String
    let symbol: String
    var running = false
    var succeeded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            if running {
                ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                    .transition(.opacity)
            } else {
                Image(systemName: succeeded ? "checkmark" : symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 12, height: 12)
                    .id(succeeded)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.65).combined(with: .opacity))
            }
            if !succeeded {
                Text(running ? runningTitle : title)
                    .transition(.opacity)
            }
        }
        .fixedSize()
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78), value: running)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.72), value: succeeded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(succeeded ? "已完成" : running ? runningTitle : title)
    }
}
