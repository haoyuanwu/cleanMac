import SwiftUI
import AppKit

/// 与扫描、清理相关的系统权限入口。
struct SettingsView: View {
    @State private var canReadTrash: Bool?
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
                    sectionHeader("系统权限", subtitle: "扫描和清理所需的访问权限由 macOS 管理。")
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
        .task {
            await refreshTrashAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshTrashAccess() }
        }
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
                    title: "完全磁盘访问权限",
                    detail: "读取废纸篓、受保护的缓存和应用数据。",
                    instruction: "在系统设置中开启后，重启应用再扫描。",
                    buttonTitle: "打开授权页面", status: trashAccessBadge
                ) { openPrivacySettings(fullDiskAccess: true) }
                permissionDivider
                PermissionRow(
                    icon: "folder.fill", tint: .green,
                    title: "文件与文件夹",
                    detail: "扫描桌面、文稿、下载及外置磁盘。",
                    instruction: "在「隐私与安全性 → 文件与文件夹」中检查访问开关。",
                    buttonTitle: "打开系统设置"
                ) { openPrivacySettings() }
                permissionDivider
                PermissionRow(
                    icon: "square.stack.3d.up.fill", tint: .purple,
                    title: "其他应用数据",
                    detail: "扫描浏览器缓存和应用残留。",
                    instruction: "访问其他应用容器时，macOS 可能单独请求授权。",
                    buttonTitle: "打开系统设置"
                ) { openPrivacySettings() }
                permissionDivider
                PermissionRow(
                    icon: "app.fill", tint: .orange,
                    title: "应用管理",
                    detail: "允许 cleanMac 将其他应用移到废纸篓。",
                    instruction: "授权后返回应用，可继续此前的卸载操作。",
                    buttonTitle: "打开授权页面"
                ) { openPrivacySettings(appManagement: true) }
                permissionDivider
                PermissionRow(
                    icon: "arrow.up.right.square", tint: .cyan,
                    title: "自动化",
                    detail: "通过 Finder 显示所选文件及其简介。",
                    instruction: "在「隐私与安全性 → 自动化」中允许控制 Finder。",
                    buttonTitle: "打开系统设置"
                ) { openPrivacySettings() }

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

    private var permissionDivider: some View {
        Divider().padding(.leading, 48)
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

    private var trashAccessBadge: AnyView? {
        switch canReadTrash {
        case true:
            return AnyView(
                StatusBadge(text: "废纸篓可读", color: .green, icon: "checkmark.circle.fill")
            )
        case false:
            return AnyView(
                StatusBadge(text: "废纸篓不可读", color: .orange, icon: "exclamationmark.triangle.fill")
            )
        case nil:
            return AnyView(
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.5)
                    Text("检查中…").font(.caption).foregroundColor(.secondary)
                }
            )
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

    private func refreshTrashAccess() async {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
        let readable = await Task.detached(priority: .utility) {
            (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
        }.value
        canReadTrash = readable
    }

    private func openPrivacySettings(fullDiskAccess: Bool = false, appManagement: Bool = false) {
        if appManagement {
            _ = PrivacySettingsOpener.openAppManagement()
            return
        }
        let base = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        let suffix: String? = fullDiskAccess ? "Privacy_AllFiles" : nil
        let destination = suffix.map { base + "?" + $0 } ?? base
        guard let url = URL(string: destination) else { return }
        let legacyBase = "x-apple.systempreferences:com.apple.preference.security"
        let legacyDestination = suffix.map { legacyBase + "?" + $0 } ?? legacyBase
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
    var status: AnyView? = nil
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
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    if let status {
                        status
                    }
                }
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
