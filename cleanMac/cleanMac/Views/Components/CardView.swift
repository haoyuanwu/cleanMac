import SwiftUI

/// 通用卡片：产品仪表盘抬升面板
struct CardView<Content: View>: View {
    var padding: CGFloat = 22
    let content: () -> Content

    init(padding: CGFloat = 22, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.surfaceRaised, Theme.surfaceRaised.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.55),
                                        Color.primary.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .cardShadow()
    }
}

/// 信息行组件
struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
                .frame(width: 20, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }
}

/// 统计数据组件
struct StatItem: View {
    let title: String
    let value: String
    let color: Color
    
    init(title: String, value: String, color: Color = .primary) {
        self.title = title
        self.value = value
        self.color = color
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
        }
    }
}

/// 状态徽章组件
struct StatusBadge: View {
    let text: String
    let color: Color
    let icon: String?
    
    init(text: String, color: Color, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundColor(color)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}
