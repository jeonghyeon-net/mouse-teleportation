import Foundation
import CoreGraphics
import Testing
@testable import TeleportCore

private func display(_ id: UInt32, _ x: Double, _ y: Double, _ width: Double = 1920, _ height: Double = 1080) -> Display {
    Display(id: id, bounds: CGRect(x: x, y: y, width: width, height: height))
}

@Test func twoDisplaysToggleBothDirections() {
    let left = display(1, 0, 0), right = display(2, 1920, 0)
    #expect(DisplayLayout.destination(from: CGPoint(x: 100, y: 200), displays: [right, left]) == right)
    #expect(DisplayLayout.destination(from: right.center, displays: [left, right]) == left)
}

@Test func negativeCoordinatesAndMixedResolutions() {
    let laptop = display(1, 0, 0, 1512, 982)
    let external = display(2, -2560, -400, 2560, 1440)
    let target = DisplayLayout.destination(from: laptop.center, displays: [laptop, external])
    #expect(target?.center == CGPoint(x: -1280, y: 320))
}

@Test func threeDisplaysCycleByPhysicalLayout() {
    let a = display(10, -1920, 0), b = display(11, 0, -1080), c = display(12, 0, 0)
    #expect(DisplayLayout.destination(from: a.center, displays: [c, a, b]) == b)
    #expect(DisplayLayout.destination(from: b.center, displays: [b, c, a]) == c)
    #expect(DisplayLayout.destination(from: c.center, displays: [b, a, c]) == a)
}

@Test func noDestinationForSingleOrMirroredDisplay() {
    #expect(DisplayLayout.destination(from: .zero, displays: []) == nil)
    #expect(DisplayLayout.destination(from: .zero, displays: [display(1, 0, 0)]) == nil)
    #expect(DisplayLayout.destination(from: .zero, displays: [display(1, 0, 0), display(2, 0, 0)]) == nil)
}

@Test func detachedDisplayFallsBackToNearestRectangle() {
    let left = display(1, 0, 0), right = display(2, 2500, 0)
    #expect(DisplayLayout.destination(from: CGPoint(x: 2300, y: 500), displays: [left, right]) == left)
}

@Test func sharedBoundaryBelongsToNextDisplay() {
    let left = display(1, 0, 0), right = display(2, 1920, 0)
    #expect(DisplayLayout.destination(from: CGPoint(x: 1920, y: 200), displays: [left, right]) == left)
}
