import SwiftUI
import Vortex

/// Vortex 撒花庆祝：删除后在屏幕不同区域连发 3 次，间隔拉开
struct CelebrationBanner: View {
    let token: Int

    @State private var system = VortexSystem.confetti.makeUniqueCopy()
    @State private var visible = false
    @State private var burstHandler: ((CGPoint) -> Void)?
    @State private var hideWork: DispatchWorkItem?

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
                        .onAppear {
                            burstHandler = { screenPoint in
                                proxy.move(to: screenPoint)
                                proxy.burst()
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .onAppear {
                if token > 0 {
                    playTripleBurst(size: geo.size)
                }
            }
            .onChange(of: token) { newValue in
                guard newValue > 0 else { return }
                playTripleBurst(size: geo.size)
            }
        }
    }

    /// 左 / 中上 / 右 三点，屏幕像素坐标；间隔 0.5s
    private func playTripleBurst(size: CGSize) {
        hideWork?.cancel()
        visible = true

        // 三点铺开：角落与中上，明显分开
        let slots: [CGPoint] = [
            CGPoint(x: size.width * 0.12, y: size.height * 0.55),
            CGPoint(x: size.width * 0.50, y: size.height * 0.22),
            CGPoint(x: size.width * 0.88, y: size.height * 0.62)
        ]
        let interval = 0.5

        DispatchQueue.main.async {
            guard burstHandler != nil else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    fireSlots(slots, interval: interval)
                }
                return
            }
            fireSlots(slots, interval: interval)
        }

        let hide = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.4)) {
                visible = false
            }
        }
        hideWork = hide
        // 3 发 × 0.5s + 粒子寿命
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 + interval * 3, execute: hide)
    }

    private func fireSlots(_ slots: [CGPoint], interval: Double) {
        for (index, slot) in slots.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * interval) {
                burstHandler?(slot)
            }
        }
    }
}
