// 설치된 앱의 실제 전역 키·포인터 이동·확대 복원을 검증한다. 실행 중 포인터가 잠깐 이동한다.
import AppKit
import Carbon
import Darwin

enum CheckFailure: Error { case failed(String) }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure.failed(message) }
    print("PASS: \(message)")
}

let bundleID = "net.jeonghyeon.MouseTeleportation"
let original = CGEvent(source: nil)!.location
let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)!
let connection = unsafeBitCast(dlsym(sky, "SLSMainConnectionID")!, to: (@convention(c) () -> Int32).self)
let readScale = unsafeBitCast(dlsym(sky, "SLSGetCursorScale")!, to: (@convention(c) (Int32, UnsafeMutablePointer<Float>) -> Int32).self)
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
        dlclose(sky)
    }
    try require(CGPreflightPostEventAccess(), "실제 입력 검사 프로세스의 이벤트 전송 권한")
    let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { !$0.isTerminated }
    try require(instances.count == 1, "설치된 앱 본체가 한 번만 실행 중")
    try require(instances[0].activationPolicy == .prohibited, "Dock·앱 전환기에 없는 background 정책")
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
    pause(0.15)
    try require(near(point(), target), "Option + Tab → 다른 화면의 정확한 중앙")
    try require(scale() > baseline + 0.5, "실제 시스템 커서 배율 증가")
    pressTab(down: true, repeatKey: true)
    pause(0.1)
    try require(near(point(), target), "길게 누른 Tab 반복 입력 억제")
    pressTab(down: false)
    pause(0.1)
    pressTab(down: true)
    pressTab(down: false)
    pause(0.15)
    let next = displays[2 % displays.count]
    try require(near(point(), CGPoint(x: next.midX, y: next.midY)), "Tab 재입력 → 다음 화면으로 순환")
    pause(1)
    try require(abs(scale() - baseline) < 0.02, "확대가 끝난 뒤 원래 커서 배율 복원")
    try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost, "사용 중인 앱 포커스 유지")
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
