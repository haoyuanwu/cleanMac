import SwiftUI

/// 智能清理确认：展示将清理的条目，用户同意后执行
struct SmartCleanConfirmDialog: View {
    let plan: SmartCleanPlan
    @Binding var selectedPaths: Set<String>
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var selectedItems: [FileItem] {
        plan.items.filter { selectedPaths.contains($0.path) }
    }

    private var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("智能清理确认")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("以下为低风险推荐项（缓存、日志等）。默认全部勾选，取消不需要的项后再清理。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }

            HStack(spacing: 10) {
                summaryChip(title: "推荐项", value: "\(plan.items.count) 项", color: Theme.accentGradient)
                summaryChip(title: "合计", value: plan.totalSizeFormatted, color: Theme.warmGradient)
                summaryChip(title: "将清理", value: FileSizeFormatter.string(fromByteCount: selectedSize), color: Theme.successGradient)
            }

            // 分类摘要
            HStack(spacing: 8) {
                ForEach(plan.categorySummary.indices, id: \.self) { index in
                    let entry = plan.categorySummary[index]
                    Text("\(entry.category.rawValue) \(entry.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(entry.category.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(entry.category.color.opacity(0.12)))
                }
            }

            HStack {
                Toggle(isOn: Binding(
                    get: {
                        !plan.items.isEmpty && plan.items.allSatisfy { selectedPaths.contains($0.path) }
                    },
                    set: { on in
                        if on {
                            selectedPaths = Set(plan.items.map(\.path))
                        } else {
                            selectedPaths.removeAll()
                        }
                    }
                )) {
                    Text("全选")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.checkbox)

                Spacer()
                Text("共 \(plan.items.count) 条 · 仅展示前 40 条明细")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(plan.items.prefix(40))) { item in
                        row(item)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 260)

            HStack(spacing: 12) {
                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button {
                    onConfirm()
                } label: {
                    Text(selectedPaths.isEmpty
                         ? "请选择要清理的项"
                         : "清理所选 \(selectedItems.count) 项 · \(FileSizeFormatter.string(fromByteCount: selectedSize))")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(selectedPaths.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .elevatedShadow()
    }

    private func row(_ item: FileItem) -> some View {
        Toggle(isOn: Binding(
            get: { selectedPaths.contains(item.path) },
            set: { on in
                if on {
                    selectedPaths.insert(item.path)
                } else {
                    selectedPaths.remove(item.path)
                }
            }
        )) {
            HStack(spacing: 10) {
                Circle()
                    .fill(riskColor(item.riskLevel))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(item.path)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.path)
                }

                Spacer(minLength: 8)

                Text(item.riskLevel.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))

                Text(item.sizeFormatted)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 72, alignment: .trailing)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func riskColor(_ risk: FileRiskLevel) -> Color {
        switch risk {
        case .safe: return .green
        case .caution: return .orange
        case .sensitive: return .red
        case .blocked: return .gray
        }
    }

    private func summaryChip(title: String, value: String, color: LinearGradient) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.accentGradientSoft.opacity(0.45))
        )
    }
}
