import SwiftUI
import AppKit

/// 与扫描、清理相关的系统权限入口。
struct SettingsView: View {
    @State private var canReadTrash: Bool?
    @State private var systemInfo: SystemInfo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // 权限
                sectionHeader("权限", subtitle: "权限由 macOS 管理。打开系统设置后，为 cleanMac 开启对应访问权限。")

                VStack(spacing: 12) {
                    PermissionRow(
                        icon: "internaldrive.fill",
                        tint: Color(red: 0.22, green: 0.52, blue: 1.0),
                        title: "完全磁盘访问权限",
                        detail: "读取废纸篓、受保护的缓存和部分应用数据。",
                        instruction: "将 cleanMac 加入列表并开启开关，重启后重新扫描。",
                        buttonTitle: "打开授权页面",
                        status: trashAccessBadge
                    ) {
                        openPrivacySettings(fullDiskAccess: true)
                    }

                    PermissionRow(
                        icon: "folder.fill",
                        tint: Color(red: 0.18, green: 0.72, blue: 0.52),
                        title: "文件与文件夹",
                        detail: "扫描桌面、文稿、下载及外置磁盘中的文件。",
                        instruction: "在「隐私与安全性 → 文件与文件夹」中检查访问开关。",
                        buttonTitle: "打开系统设置"
                    ) {
                        openPrivacySettings()
                    }

                    PermissionRow(
                        icon: "square.stack.3d.up.fill",
                        tint: Color(red: 0.55, green: 0.38, blue: 0.98),
                        title: "其他应用数据",
                        detail: "扫描浏览器缓存和已卸载应用留下的数据目录。",
                        instruction: "访问其他应用容器时，macOS 可能单独弹出授权请求。",
                        buttonTitle: "打开系统设置"
                    ) {
                        openPrivacySettings()
                    }

                    PermissionRow(
                        icon: "app.fill",
                        tint: Color(red: 1.0, green: 0.45, blue: 0.35),
                        title: "应用管理",
                        detail: "允许 cleanMac 将其他应用移到废纸篓。",
                        instruction: "允许后返回应用会自动重试卸载；系统可能要求管理员密码。",
                        buttonTitle: "打开授权页面"
                    ) {
                        openPrivacySettings(appManagement: true)
                    }

                    PermissionRow(
                        icon: "arrow.up.right.square",
                        tint: Color(red: 0.95, green: 0.55, blue: 0.20),
                        title: "自动化",
                        detail: "通过 Finder 显示所选文件及其简介。",
                        instruction: "在「隐私与安全性 → 自动化」中允许 cleanMac 控制 Finder。",
                        buttonTitle: "打开系统设置"
                    ) {
                        openPrivacySettings()
                    }
                }

                // 管理员说明
                CardView {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.accentGradient)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.accentGradientSoft)
                            )
                        VStack(alignment: .leading, spacing: 6) {
                            Text("管理员授权")
                                .font(.system(size: 14, weight: .semibold))
                            Text("清理受保护的系统目录，或卸载需要管理员权限的应用时，macOS 会在操作过程中弹出授权框。")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineSpacing(3)
                        }
                        Spacer(minLength: 0)
                    }
                }

                // 运行日志
                CardView {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.accentGradient)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.accentGradientSoft)
                            )
                        VStack(alignment: .leading, spacing: 6) {
                            Text("运行日志")
                                .font(.system(size: 14, weight: .semibold))
                            Text("记录删除拦截、清理失败与权限问题，便于排查。")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("打开日志文件") {
                            AppLog.revealLogFile()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // 关于本机
                sectionHeader("关于本机", subtitle: "当前设备与系统版本信息。")
                aboutMacCard
            }
            .frame(maxWidth: 780)
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("")
        .background(Theme.canvas.ignoresSafeArea())
        .task {
            await refreshTrashAccess()
            if systemInfo == nil {
                let service = SystemInfoService()
                systemInfo = await Task.detached { service.getSystemInfo() }.value
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshTrashAccess() }
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

    // MARK: - 关于本机
    private var aboutMacCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 16) {
                if let info = systemInfo {
                    HStack(spacing: 14) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.accentGradient)
                            .frame(width: 48, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.accentGradientSoft)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(info.model)
                                .font(.system(size: 17, weight: .semibold))
                            Text("\(info.chip) · \(info.memory)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("macOS \(info.macOSVersion)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.primary.opacity(0.05)))
                    }

                    Divider()

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        infoChip("CPU 核心", "\(info.cpuCores) 核")
                        infoChip("运行时间", info.uptime)
                        infoChip("主机名", info.hostname)
                        infoChip("构建号", info.buildNumber)
                        infoChip("序列号", info.serialNumber)
                        infoChip("系统", "macOS \(info.macOSVersion)")
                    }
                } else {
                    HStack {
                        Spacer()
                        ProgressView("正在获取系统信息…")
                            .padding(.vertical, 20)
                        Spacer()
                    }
                }
            }
        }
    }

    private func infoChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accentGradientSoft.opacity(0.45))
        )
    }

    private var trashAccessText: String {
        switch canReadTrash {
        case true: return "废纸篓读取测试：可读取"
        case false: return "废纸篓读取测试：无法读取"
        case nil: return "正在检查废纸篓读取权限…"
        }
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

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    if let status {
                        status
                    }
                }
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(instruction)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.9))
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isHovered ? Theme.surfaceRaised : Theme.surfaceRaised.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
        .cardShadow()
        .onHover { hovering in
            withAnimation(Theme.ease) { isHovered = hovering }
        }
    }
}
