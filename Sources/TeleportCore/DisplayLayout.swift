import Foundation
import CoreGraphics

public struct Display: Equatable, Sendable {
    public let id: UInt32
    public let bounds: CGRect

    public init(id: UInt32, bounds: CGRect) {
        self.id = id
        self.bounds = bounds
    }

    public var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }
}

public enum DisplayLayout {
    /// Quartz 전역 좌표를 일관되게 사용한다. 화면 왼쪽부터, 같은 x에서는 위부터 순환한다.
    public static func destination(from point: CGPoint, displays: [Display]) -> Display? {
        var seen = Set<CGRectKey>()
        let ordered = displays.filter {
            !$0.bounds.isEmpty && !$0.bounds.isInfinite && !$0.bounds.isNull &&
            seen.insert(CGRectKey($0.bounds)).inserted
        }.sorted {
            if $0.bounds.minX != $1.bounds.minX { return $0.bounds.minX < $1.bounds.minX }
            if $0.bounds.minY != $1.bounds.minY { return $0.bounds.minY < $1.bounds.minY }
            return $0.id < $1.id
        }
        guard ordered.count > 1 else { return nil }
        // 디스플레이 분리 직후 좌표가 빈 공간에 남으면 가장 가까운 화면을 현재 화면으로 본다.
        let current = ordered.firstIndex { $0.bounds.contains(point) }
            ?? ordered.indices.min { distance(point, ordered[$0].bounds) < distance(point, ordered[$1].bounds) }
        guard let current else { return nil }
        return ordered[(current + 1) % ordered.count]
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    private struct CGRectKey: Hashable {
        let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
        init(_ rect: CGRect) {
            x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
        }
    }
}
