// 설치된 앱의 실제 전역 키·포인터 이동·확대 복원을 검증한다. 실행 중 포인터가 잠깐 이동한다.
import AppKit
import Carbon
import Darwin
import IOKit

enum CheckFailure: Error { case failed(String) }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure.failed(message) }
    print("PASS: \(message)")
}

let bundleID = "net.jeonghyeon.MouseTeleportation"
let original = CGEvent(source: nil)!.location
let frontmost = NSWorkspace.shared.frontmostApplication
let primaryDisplay = CGMainDisplayID()
let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)!
let connection = unsafeBitCast(dlsym(sky, "SLSMainConnectionID")!, to: (@convention(c) () -> Int32).self)
let readScale = unsafeBitCast(dlsym(sky, "SLSGetCursorScale")!, to: (@convention(c) (Int32, UnsafeMutablePointer<Float>) -> Int32).self)
let readDisplay = unsafeBitCast(dlsym(sky, "SLSCopyActiveMenuBarDisplayIdentifier")!, to: (@convention(c) (Int32) -> Unmanaged<CFString>?).self)
let setDisplay = unsafeBitCast(dlsym(sky, "SLSSetActiveMenuBarDisplayIdentifier")!, to: (@convention(c) (Int32, CFString, UInt64) -> Void).self)
let timestamp = unsafeBitCast(dlsym(sky, "SLSCurrentEventTimestamp")!, to: (@convention(c) () -> UInt64).self)
func activeDisplay() -> CGDirectDisplayID? {
    guard let identifier = readDisplay(connection())?.takeRetainedValue(),
          let uuid = CFUUIDCreateFromString(nil, identifier) else { return nil }
    return CGDisplayGetDisplayIDFromUUID(uuid)
}
let originalActiveDisplay = readDisplay(connection())?.takeRetainedValue()
func scale() -> Float {
    var value: Float = 0
    _ = readScale(connection(), &value)
    return value
}
Thread.sleep(forTimeInterval: 1.1)
let baseline = scale()
func pressTab(down: Bool, repeatKey: Bool = false) {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Tab), keyDown: down)!
    event.flags = .maskAlternate
    if repeatKey { event.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
    event.post(tap: .cghidEventTap)
}
func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }
func point() -> CGPoint { CGEvent(source: nil)!.location }
func near(_ a: CGPoint, _ b: CGPoint) -> Bool { hypot(a.x - b.x, a.y - b.y) < 2 }

do {
    defer {
        pressTab(down: false)
        pause(1)
        CGWarpMouseCursorPosition(original)
        if let originalActiveDisplay { setDisplay(connection(), originalActiveDisplay, timestamp()) }
        frontmost?.activate(options: [])
        dlclose(sky)
    }
    try require(CGPreflightPostEventAccess(), "실제 입력 검사 프로세스의 이벤트 전송 권한")
    let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { !$0.isTerminated && $0.activationPolicy == .accessory }
    try require(instances.count == 1, "설치된 앱 본체가 한 번만 실행 중")
    try require(instances[0].activationPolicy == .accessory, "Dock·앱 전환기에 없는 accessory 정책")
    let appPID = instances[0].processIdentifier
    func overlayBounds() -> [CGRect] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? Int32) == appPID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any] else { return nil }
            return CGRect(dictionaryRepresentation: bounds as CFDictionary)
        }
    }
    var ids = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    _ = CGGetActiveDisplayList(32, &ids, &count)
    let activeIDs: [CGDirectDisplayID] = ids.prefix(Int(count)).filter { CGDisplayMirrorsDisplay($0) == 0 }
    let rectangles: [CGRect] = activeIDs.map { CGDisplayBounds($0) }
    let displays: [CGRect] = rectangles.sorted { (left: CGRect, right: CGRect) in
        if left.minX == right.minX { return left.minY < right.minY }
        return left.minX < right.minX
    }
    try require(displays.count >= 2, "두 개 이상의 확장 디스플레이")
    let start = CGPoint(x: displays[0].midX, y: displays[0].midY)
    let target = CGPoint(x: displays[1].midX, y: displays[1].midY)
    CGWarpMouseCursorPosition(start)
    pause(0.1)
    pressTab(down: true)
    pause(0.09)
    try require(near(point(), target), "Option + Tab → 다른 화면의 정확한 중앙")
    try require(overlayBounds() == [displays[1]], "도착 화면에만 정확한 크기의 테두리 오버레이 표시")
    try require(activeDisplay().map { CGDisplayBounds($0) } == displays[1], "도착 화면의 macOS 메뉴 막대 활성 상태 전환")
    try require(NSWorkspace.shared.frontmostApplication?.processIdentifier != appPID, "본체와 효과 패널이 앱 포커스를 가져가지 않음")
    // 새로 설치한 앱의 helper 첫 실행은 평소보다 늦을 수 있다.
    let enlargementDeadline = ProcessInfo.processInfo.systemUptime + 0.35
    while scale() <= baseline + 0.5 && ProcessInfo.processInfo.systemUptime < enlargementDeadline { pause(0.02) }
    try require(scale() > baseline + 0.5, "실제 시스템 커서 배율 증가")
    pressTab(down: true, repeatKey: true)
    pause(0.1)
    try require(near(point(), target), "길게 누른 Tab 반복 입력 억제")
    try require(activeDisplay().map { CGDisplayBounds($0) } == displays[1], "키 반복 중 활성 디스플레이 유지")
    pressTab(down: false)
    pause(0.1)
    pressTab(down: true)
    pressTab(down: false)
    pause(0.09)
    let next = displays[2 % displays.count]
    let nextCenter = CGPoint(x: next.midX, y: next.midY)
    try require(near(point(), nextCenter), "Tab 재입력 → 다음 화면으로 순환 (\(point()) / \(nextCenter))")
    try require(overlayBounds() == [next], "연속 이동 시 이전 화면 효과를 없애고 도착 화면에만 표시")
    try require(activeDisplay().map { CGDisplayBounds($0) } == next, "연속 이동 시 활성 디스플레이도 다음 화면으로 전환")
    var finalDisplay = next
    for step in 1...6 {
        pause(0.06)
        pressTab(down: true)
        pressTab(down: false)
        pause(0.09)
        finalDisplay = displays[(2 + step) % displays.count]
        let center = CGPoint(x: finalDisplay.midX, y: finalDisplay.midY)
        try require(near(point(), center) && activeDisplay().map { CGDisplayBounds($0) } == finalDisplay,
                    "빠른 반복 전환 \(step)/6: 커서 중앙과 활성 디스플레이 일치 (\(point()) / \(center))")
    }
    pause(1)
    try require(overlayBounds().isEmpty, "효과 종료 후 오버레이 창 제거")
    let restoredScale = scale()
    try require(abs(restoredScale - baseline) < 0.02, "확대가 끝난 뒤 원래 커서 배율 복원 (\(baseline) → \(restoredScale))")
    try require(activeDisplay().map { CGDisplayBounds($0) } == finalDisplay, "효과 종료 후에도 도착 화면의 활성 상태 유지")
    try require(CGMainDisplayID() == primaryDisplay, "시스템 설정의 주 디스플레이 구성 유지")
    try require(NSWorkspace.shared.frontmostApplication?.processIdentifier != appPID, "백그라운드 앱이 전면에 나타나지 않음")
    if CommandLine.arguments.contains("--check-crash-recovery") {
        let executable = instances[0].bundleURL!
        // 오직 방금 검증한 앱 본체만 종료하고, 성공·실패와 관계없이 다시 실행한다.
        defer {
            let restart = Process()
            restart.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            restart.arguments = ["-g", executable.path]
            try? restart.run()
            restart.waitUntilExit()
        }
        pressTab(down: true)
        pressTab(down: false)
        pause(0.15)
        try require(scale() > baseline + 0.5, "비정상 종료 검사 전 확대 활성화")
        kill(instances[0].processIdentifier, SIGKILL)
        pause(1)
        try require(abs(scale() - baseline) < 0.02, "본체 SIGKILL 이후에도 helper가 커서 배율 복원")
    }
    print("실제 전역 입력 검사 완료")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
