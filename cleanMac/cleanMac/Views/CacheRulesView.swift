import SwiftUI
import Combine

struct CacheRulesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVersion = CacheRuleStore.shared.activeCatalog.version
    @State private var activeVersion = CacheRuleStore.shared.activeCatalog.version
    private let store = CacheRuleStore.shared

    private var catalog: CacheRuleCatalog {
        store.catalogs.first { $0.version == selectedVersion } ?? .baseline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("本地缓存规则").font(.system(size: 21, weight: .bold))
                    Text("查看识别范围、清理影响，或回退到基础名称识别。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 12) {
                Picker("规则版本", selection: $selectedVersion) {
                    ForEach(store.catalogs, id: \.version) { version in
                        Text("\(version.title) · \(version.version)").tag(version.version)
                    }
                }.labelsHidden().accessibilityLabel("选择本地缓存规则版本")
                Button(selectedVersion == activeVersion ? "已启用" : "启用此版本") {
                    store.activate(selectedVersion)
                    activeVersion = store.activeCatalog.version
                }.disabled(selectedVersion == activeVersion)
            }
            Text("当前启用：\(activeVersion)。切换后会重置应用缓存结果和自动忽略记录，请重新扫描。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(store.loadErrors, id: \.self) { error in
                Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.orange)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if catalog.rules.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("基础名称识别", systemImage: "folder.badge.magnifyingglass").font(.system(size: 16, weight: .semibold))
                            Text("继续查找标准缓存目录，以及明确包含 cache 或缓存名称的项目。此版本不增加专用路径。")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
                    }
                    ForEach(catalog.rules) { rule in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(rule.title).font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Label(rule.risk == .sensitive ? "谨慎 · 手动确认" : "请确认", systemImage: "hand.raised")
                                    .font(.system(size: 12)).foregroundStyle(.orange)
                            }
                            Text(rule.reason).font(.system(size: 13))
                            Text(rule.impact).font(.system(size: 12)).foregroundStyle(.secondary)
                            DisclosureGroup("匹配路径与软件") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(rule.relativePaths.joined(separator: "\n"))
                                    Text("软件标识：" + rule.bundleIdentifiers.joined(separator: "、"))
                                    Text("规则：\(rule.id) · 版本 \(catalog.version)")
                                    ForEach(rule.sources, id: \.self) { source in
                                        if let url = URL(string: source) { Link("参考来源 · \(url.host ?? "")", destination: url) }
                                    }
                                }.font(.system(size: 12)).textSelection(.enabled).padding(.top, 8)
                            }.font(.system(size: 12))
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            Text("规则随应用发布并在本机校验；仅在所属软件的数据目录匹配，不修改 .app 内资源。回退不会清除已存在的清理记录。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(24).frame(width: 740, height: 580).background(Theme.canvas)
            .onReceive(NotificationCenter.default.publisher(for: CacheRuleStore.didChange).receive(on: RunLoop.main)) { _ in
                activeVersion = store.activeCatalog.version
            }
    }
}

struct CacheRuleExplanationView: View {
    let file: FileItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("缓存识别依据").font(.system(size: 20, weight: .bold))
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let match = file.cacheRuleMatch {
                Label(match.title, systemImage: "doc.text.magnifyingglass").font(.system(size: 15, weight: .semibold))
                Text(file.path).font(.system(size: 12)).textSelection(.enabled)
                Divider()
                Text(match.reason).font(.system(size: 13))
                Label(match.risk.displayName, systemImage: "hand.raised").font(.system(size: 13, weight: .medium)).foregroundStyle(.orange)
                Text(match.impact).font(.system(size: 13)).foregroundStyle(.secondary)
                Text("规则 \(match.ruleID) · 版本 \(match.version)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.padding(24).frame(width: 580).background(Theme.canvas)
    }
}
