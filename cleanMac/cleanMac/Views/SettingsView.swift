import SwiftUI
import AppKit

/// 与扫描、清理相关的系统权限入口。
struct SettingsView: View {
    @State private var canReadTrash: Bool?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("设置")
                        .font(.system(size: 24, weight: .bold))
                    Text("权限由 macOS 管理。点击下方按钮打开系统设置，再为 cleanMac 开启对应访问权限。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                CardView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("权限")
                            .font(.headline)

                        PermissionRow(
                            icon: "internaldrive.fill",
                            title: "完全磁盘访问权限",
                            detail: "读取废纸篓、受保护的缓存和部分应用数据。",
                            instruction: "打开后将 cleanMac 加入列表并开启开关，重启应用后重新扫描。",
                            buttonTitle: "打开授权页面"
                        ) {
                            openPrivacySettings(fullDiskAccess: true)
                        }

                        HStack(spacing: 6) {
                            Image(systemName: canReadTrash == true ? "checkmark.circle.fill" : "info.circle.fill")
                                .foregroundColor(canReadTrash == true ? .green : .secondary)
                            Text(trashAccessText)
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        .padding(.leading, 42)

                        Divider()

                        PermissionRow(
                            icon: "folder.fill",
                            title: "文件与文件夹",
                            detail: "扫描桌面、文稿、下载及外置磁盘中的文件。",
                            instruction: "在「隐私与安全性 → 文件与文件夹」中检查 cleanMac 的访问开关。",
                            buttonTitle: "打开系统设置"
                        ) {
                            openPrivacySettings()
                        }

                        Divider()

                        PermissionRow(
                            icon: "square.stack.3d.up.fill",
                            title: "其他应用数据",
                            detail: "扫描浏览器缓存和已卸载应用留下的数据目录。",
                            instruction: "访问其他应用容器时，macOS 可能单独弹出授权请求。",
                            buttonTitle: "打开系统设置"
                        ) {
                            openPrivacySettings()
                        }

                        Divider()

                        PermissionRow(
                            icon: "app.fill",
                            title: "应用管理",
                            detail: "允许 cleanMac 将其他应用移到废纸篓。",
                            instruction: "在「隐私与安全性 → 应用管理」中允许 cleanMac；返回应用后会自动重试卸载。系统可能还会要求管理员密码。",
                            buttonTitle: "打开授权页面"
                        ) {
                            openPrivacySettings(appManagement: true)
                        }

                        Divider()

                        PermissionRow(
                            icon: "arrow.up.right.square",
                            title: "自动化",
                            detail: "通过 Finder 显示所选文件及其简介。",
                            instruction: "在「隐私与安全性 → 自动化」中允许 cleanMac 控制 Finder。",
                            buttonTitle: "打开系统设置"
                        ) {
                            openPrivacySettings()
                        }
                    }
                }

                CardView {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("管理员授权")
                                .font(.system(size: 13, weight: .semibold))
                            Text("清理受保护的系统目录或卸载需要管理员权限的应用时，macOS 会在操作时弹出管理员授权框。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: 760)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("设置")
        .task { await refreshTrashAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshTrashAccess() }
        }
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

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let instruction: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(instruction)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
