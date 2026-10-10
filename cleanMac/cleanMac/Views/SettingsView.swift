import SwiftUI
import AppKit

/// 与扫描、清理相关的系统权限入口。
struct SettingsView: View {
    @State private var isHistoryExpanded = false
    @ObservedObject private var growthMonitor = StorageGrowthMonitor.shared
    @ObservedObject private var trashMonitor = TrashMonitor.shared

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                pageHeader

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("提醒与监测", subtitle: "按需调整空间提醒，设置会立即生效。")
                    LazyVGrid(columns: settingsColumns, alignment: .leading, spacing: 14) {
                        trashWarningCard
                        growthWarningCard
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("系统权限", subtitle: "仅在扫描提示无法读取受保护内容时检查。")
                    permissionsCard
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("工具与应用", subtitle: "查看运行记录和当前版本。")
                    LazyVGrid(columns: settingsColumns, alignment: .leading, spacing: 14) {
                        logCard
                        aboutAppCard
                    }
                }
            }
            .frame(maxWidth: 960)
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("")
        .background(Theme.reviewCanvas(.blue))
    }

    private var settingsColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 300), spacing: 14)]
    }

    private var pageHeader: some View {
        HStack(spacing: 16) {
            Image("SidebarSettings")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(.white)
                .frame(width: 23, height: 23)
                .frame(width: 48, height: 48)
                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .elevatedShadow()

            VStack(alignment: .leading, spacing: 4) {
                Text("设置")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("空间提醒、系统权限与应用信息")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var trashWarningCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 16) {
                cardHeading("废纸篓警戒", subtitle: "每 30 分钟检查一次占用", icon: "trash.fill", tint: .red)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(trashMonitor.status.map { FileSizeFormatter.string(fromByteCount: $0.bytes) } ?? "正在读取…")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("当前废纸篓占用")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if trashMonitor.isOverLimit {
                        Label("已超限", systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.red)
                    } else if let percentage = trashMonitor.percentage {
                        Text("\(percentage)%")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                HStack {
                    Text("警戒大小")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(trashMonitor.limit.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accentGradient)
                }
                Slider(value: trashLimitPosition, in: 0...4, step: 1)
                    .tint(.blue)
                    .accessibilityLabel("废纸篓警戒大小")
                    .accessibilityValue(trashMonitor.limit.title)
                HStack(spacing: 0) {
                    ForEach(TrashWarningLimit.allCases) { limit in
                        Text(limit.title)
                            .font(.system(size: 10, weight: trashMonitor.limit == limit ? .semibold : .regular))
                            .foregroundColor(trashMonitor.limit == limit ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                Text("默认 10 GB；选择「不限」时不发送超限通知。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var growthWarningCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 16) {
                cardHeading("空间增长提醒", subtitle: "监测磁盘已用空间的变化", icon: "chart.line.uptrend.xyaxis", tint: .orange)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("定时检查")
                            .font(.system(size: 13, weight: .semibold))
                        Text("每 30 分钟记录一次")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("定时检查", isOn: Binding(
                        get: { growthMonitor.isEnabled },
                        set: { growthMonitor.setEnabled($0) }
                    ))
                    .labelsHidden()
                }

                Divider()

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(FileSizeFormatter.string(fromByteCount: growthMonitor.growthBytes))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("当前累计增长")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("超过 5 GB 提醒")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                }

                if let sample = growthMonitor.lastSample {
                    Text("上次检查：\(sample.timestamp.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if !growthMonitor.recentChanges.isEmpty {
                    DisclosureGroup("最近检查记录", isExpanded: $isHistoryExpanded) {
                        VStack(spacing: 8) {
                            ForEach(growthMonitor.recentChanges) { change in
                                HStack {
                                    Text(change.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    Spacer()
                                    Text("\(change.deltaBytes >= 0 ? "+" : "−")\(FileSizeFormatter.string(fromByteCount: abs(change.deltaBytes)))")
                                        .monospacedDigit()
                                        .foregroundColor(change.deltaBytes > 0 ? .orange : .secondary)
                                }
                                .font(.system(size: 11))
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
            }
        }
    }

    private var permissionsCard: some View {
        settingsCard {
            VStack(spacing: 0) {
                PermissionRow(
                    icon: "internaldrive.fill", tint: .blue,
                    title: "完全磁盘访问",
                    detail: "部分废纸篓位置及受保护的应用数据可能需要此权限。",
                    instruction: "仅在扫描提示无法读取时开启；开启后重启 cleanMac 再扫描。",
                    buttonTitle: "打开完全磁盘访问设置"
                ) { openFullDiskAccessSettings() }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.blue)
                    Text("清理受保护的目录或卸载部分应用时，macOS 会在操作过程中请求管理员授权。")
                        .foregroundColor(.secondary)
                }
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.accentGradientSoft.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 12)
            }
        }
    }

    private var logCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 14) {
                cardHeading("运行日志", subtitle: "查看清理与权限问题的记录", icon: "doc.text.magnifyingglass", tint: .purple)
                Text("删除拦截、清理失败和权限问题会记录在日志中，便于排查。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Button {
                    AppLog.revealLogFile()
                } label: {
                    Label("打开日志文件", systemImage: "arrow.up.right")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.cardStroke))
            .cardShadow()
    }

    private func cardHeading(_ title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 分区标题
    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.accentGradient)
                .textCase(.uppercase)
                .kerning(0.6)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(2)
        }
    }

    // MARK: - 关于应用
    private var aboutAppCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("cleanMac")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("Mac 空间清理与设备信息")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Divider()
                HStack(spacing: 12) {
                    Label("版本 \(appVersion)", systemImage: "app.badge")
                    Label("构建 \(buildNumber)", systemImage: "number")
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
            }
        }
    }

    private var trashLimitPosition: Binding<Double> {
        Binding(
            get: {
                Double(TrashWarningLimit.allCases.firstIndex(of: trashMonitor.limit) ?? 1)
            },
            set: { position in
                let index = min(max(Int(position.rounded()), 0), TrashWarningLimit.allCases.count - 1)
                trashMonitor.setLimit(TrashWarningLimit.allCases[index])
            }
        )
    }

    private func openFullDiskAccessSettings() {
        let base = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        let destination = base + "?Privacy_AllFiles"
        guard let url = URL(string: destination) else { return }
        let legacyBase = "x-apple.systempreferences:com.apple.preference.security"
        let legacyDestination = legacyBase + "?Privacy_AllFiles"
        if !NSWorkspace.shared.open(url), let fallback = URL(string: legacyDestination) {
            NSWorkspace.shared.open(fallback)
        }
    }
}

// MARK: - 权限行
private struct PermissionRow: View {
    let icon: String
    var tint: Color = .accentColor
    let title: String
    let detail: String
    let instruction: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(instruction)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: action) {
                Label("打开", systemImage: "arrow.up.right")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(buttonTitle)
        }
        .padding(.vertical, 11)
    }
}
