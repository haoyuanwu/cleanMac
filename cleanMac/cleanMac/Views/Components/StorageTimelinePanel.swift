import SwiftUI

/// 占用变化中的统一表面，复用应用玻璃材质，阴影不随鼠标进出跳变。
struct StorageTimelinePanel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GradientGlassSurface(cornerRadius: 18))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}
