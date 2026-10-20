import SwiftUI
import Vortex

/// Vortex 撒花庆祝：删除后在屏幕不同区域连发 3 次，间隔拉开
struct CelebrationBanner: View {
    let token: Int

    @State private var system = VortexSystem.confetti.makeUniqueCopy()
    @State private var visible = false
    @State private var burstHandler: ((CGPoint) -> Void)?
    @State private var hideWork: DispatchWorkItem?
    @State private var burstWorkItems: [DispatchWorkItem] = []
    @State private var pendingSlots: [CGPoint]?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if visible {
                    VortexViewReader { proxy in
                        VortexView(system) {
                            Rectangle()
                                .fill(.white)
                                .frame(width: 16, height: 16)
                                .tag("square")

                            Circle()
                                .fill(.white)
                                .frame(width: 16)
                                .tag("circle")
                        }
                        .ignoresSafeArea()
                        .task(id: proxy.particleSystem != nil) {
                            guard proxy.particleSystem != nil else { return }
                            burstHandler = { screenPoint in
                                proxy.move(to: screenPoint)
                                proxy.burst()
                            }
                            if let pendingSlots {
                                fireSlots(pendingSlots)
                                self.pendingSlots = nil
                            }
                        }
                        .onDisappear {
                            burstHandler = nil
                        }
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .onChange(of: token) { newValue in
                guard newValue > 0 else { return }
                playTripleBurst(size: geo.size)
            }
            .onDisappear {
                hideWork?.cancel()
                burstWorkItems.forEach { $0.cancel() }
                burstWorkItems = []
                pendingSlots = nil
                visible = false
            }
        }
    }

    /// 左上 / 中下 / 右上三处，位置基于整个窗口的像素坐标。
    private func playTripleBurst(size: CGSize) {
        hideWork?.cancel()
        burstWorkItems.forEach { $0.cancel() }
        burstWorkItems = []
        visible = true

        let slots: [CGPoint] = [
            CGPoint(x: size.width * 0.14, y: size.height * 0.26),
            CGPoint(x: size.width * 0.52, y: size.height * 0.60),
            CGPoint(x: size.width * 0.87, y: size.height * 0.25)
        ]
        if burstHandler == nil {
            pendingSlots = slots
        } else {
            fireSlots(slots)
        }

        let hide = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.4)) {
                visible = false
            }
        }
        hideWork = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: hide)
    }

    private func fireSlots(_ slots: [CGPoint]) {
        for (index, slot) in slots.enumerated() {
            let burst = DispatchWorkItem {
                burstHandler?(slot)
            }
            burstWorkItems.append(burst)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08 + Double(index) * 0.65, execute: burst)
        }
    }
}
