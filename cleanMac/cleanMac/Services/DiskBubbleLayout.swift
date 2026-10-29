import Foundation
import CoreGraphics

/// 按面积比例放置圆形；整体缩放到视口，避免单个气泡拉伸或互相遮挡。
enum DiskBubbleLayout {
    struct Bubble: Identifiable {
        let id: String
        let center: CGPoint
        let radius: CGFloat
    }

    nonisolated static func arrange(weights: [(id: String, size: Int64)], in size: CGSize) -> [Bubble] {
        guard size.width > 0, size.height > 0 else { return [] }
        let sorted = weights.filter { $0.size > 0 }.sorted {
            $0.size == $1.size ? $0.id < $1.id : $0.size > $1.size
        }
        guard let largest = sorted.first else { return [] }
        let aspect = size.width / size.height
        var placed: [Bubble] = []
        var bounds = CGRect.zero
        let gap: CGFloat = 4

        for item in sorted {
            let radius = CGFloat(sqrt(Double(item.size) / Double(largest.size))) * 100
            if placed.isEmpty {
                placed.append(Bubble(id: item.id, center: .zero, radius: radius))
                bounds = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
                continue
            }
            var bestPoint = CGPoint(x: bounds.maxX + radius + gap, y: 0)
            var bestBounds = bounds.union(CGRect(x: bestPoint.x - radius, y: -radius, width: radius * 2, height: radius * 2))
            var bestScore = CGFloat.greatestFiniteMagnitude
            for neighbor in placed {
                for step in 0..<64 {
                    let angle = CGFloat(step) / 64 * .pi * 2
                    let distance = neighbor.radius + radius + gap
                    let point = CGPoint(x: neighbor.center.x + cos(angle) * distance,
                                        y: neighbor.center.y + sin(angle) * distance)
                    guard placed.allSatisfy({ other in
                        hypot(point.x - other.center.x, point.y - other.center.y) >= radius + other.radius + gap - 0.01
                    }) else { continue }
                    let candidate = bounds.union(CGRect(x: point.x - radius, y: point.y - radius,
                                                        width: radius * 2, height: radius * 2))
                    let score = max(candidate.width / aspect, candidate.height)
                        + (candidate.width * candidate.height).squareRoot() * 0.12
                    if score < bestScore {
                        bestPoint = point
                        bestBounds = candidate
                        bestScore = score
                    }
                }
            }
            placed.append(Bubble(id: item.id, center: bestPoint, radius: radius))
            bounds = bestBounds
        }

        let scale = min(size.width / bounds.width, size.height / bounds.height) * 0.94
        return placed.map {
            Bubble(id: $0.id,
                   center: CGPoint(x: size.width / 2 + ($0.center.x - bounds.midX) * scale,
                                   y: size.height / 2 + ($0.center.y - bounds.midY) * scale),
                   radius: $0.radius * scale)
        }
    }
}
