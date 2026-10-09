import SwiftUI

/// 白名单模块：展示受保护路径，自动计算体积，可移出
struct WhitelistView: View {
    @State private var entries: [String] = []
    @State private var sizes: [String: Int64] = [:]
    @State private var isLoading = false
    @State private var appeared = false

    private var totalSize: Int64 {
        entries.reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader

                HStack(spacing: 12) {
                    MetricTile(
                        title: "白名单条目",
                        value: "\(entries.count)",
                        subtitle: "永不清理 / 卸载",
                        gradient: Theme.accentGradient,
                        compact: true
                    )
                    MetricTile(
                        title: "占用合计",
                        value: FileSizeFormatter.string(fromByteCount: totalSize),
                        subtitle: isLoading ? "计算中…" : "文件与目录体积",
                        gradient: Theme.warmGradient,
                        compact: true
                    )
                }

                if isLoading && entries.isEmpty {
                    ProgressView("正在读取白名单…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if entries.isEmpty {
                    emptyState
                } else {
                    listView
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 40)
            .frame(maxWidth: 880)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("")
        .background(Theme.reviewCanvas(.green))
        .task {
            guard !appeared else { return }
            appeared = true
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            Task { await reload() }
        }
    }

    // MARK: - 页头
    private var pageHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 22))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.2, green: 0.7, blue: 0.55), Color(red: 0.15, green: 0.5, blue: 0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .elevatedShadow()

            VStack(alignment: .leading, spacing: 4) {
                Text("白名单")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("在文件列表或磁盘地图中右键加入；这些路径永远不会被清理")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            DetailTextButton(title: "刷新大小", systemImage: "arrow.clockwise") {
                Task { await reload() }
            }
            .disabled(isLoading)
        }
    }

    // MARK: - 列表
    private var listView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("受保护路径")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("按名称")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.8))
            }

            ForEach(entries, id: \.self) { path in
                row(path)
            }
        }
    }

    private func row(_ path: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: path))
                .font(.system(size: 14))
                .foregroundColor(.green)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.green.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName(path))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
            }

            Spacer(minLength: 8)

            if sizes[path] == nil {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 72, alignment: .trailing)
            } else {
                Text(FileSizeFormatter.string(fromByteCount: sizes[path] ?? 0))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 80, alignment: .trailing)
            }

            Button {
                UserWhitelist.remove(path)
                withAnimation(Theme.spring) {
                    entries.removeAll { $0 == path }
                    sizes[path] = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("移出白名单")
            .accessibilityLabel("移出白名单 \(displayName(path))")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
        .cardShadow()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 110, height: 110)
                    .blur(radius: 14)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
            }

            Text("暂无白名单")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("在文件列表或磁盘地图中右键 →「加入白名单」，可保护指定路径不被清理。")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    // MARK: - 数据
    private func reload() async {
        isLoading = true
        let list = UserWhitelist.allEntries()
        entries = list
        let map = await UserWhitelist.sizeMap(for: list)
        sizes = map
        isLoading = false
    }

    private func displayName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private func iconName(for path: String) -> String {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            return "folder.fill"
        }
        return "doc.fill"
    }
}
