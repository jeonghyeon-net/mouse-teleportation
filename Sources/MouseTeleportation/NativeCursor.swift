import Foundation
import Darwin

/// 실제 WindowServer 커서를 확대한다. 공개 API가 아니므로 심볼이 없으면 이동 기능만 유지한다.
final class NativeCursor {
    typealias Connection = @convention(c) () -> Int32
    typealias GetScale = @convention(c) (Int32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetScale = @convention(c) (Int32, Float) -> Int32
    private let handle: UnsafeMutableRawPointer
    private let connection: Connection
    private let getScale: GetScale
    private let setScale: SetScale

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW | RTLD_LOCAL) else { return nil }
        guard let connection = dlsym(handle, "SLSMainConnectionID"),
              let getScale = dlsym(handle, "SLSGetCursorScale"),
              let setScale = dlsym(handle, "SLSSetCursorScale") else {
            dlclose(handle)
            return nil
        }
        self.handle = handle
        self.connection = unsafeBitCast(connection, to: Connection.self)
        self.getScale = unsafeBitCast(getScale, to: GetScale.self)
        self.setScale = unsafeBitCast(setScale, to: SetScale.self)
    }

    deinit { dlclose(handle) }

    func scale() -> Float? {
        var result: Float = 1
        guard getScale(connection(), &result) == 0, result.isFinite, result >= 0.5 else { return nil }
        return result
    }

    @discardableResult func set(_ scale: Float) -> Bool {
        setScale(connection(), scale) == 0
    }
}

@MainActor
final class CursorPulse {
    private var process: Process?

    func show() {
        if let process, process.isRunning {
            kill(process.processIdentifier, SIGUSR1)
            return
        }
        guard let executable = Bundle.main.executableURL else { return }
        let child = Process()
        child.executableURL = executable
        child.arguments = ["--cursor-pulse"]
        do {
            try child.run()
            process = child
        } catch { report("커서 확대 프로세스를 시작하지 못했습니다: \(error)") }
    }

    func stop() {
        if let process, process.isRunning { process.terminate() }
    }
}

/// 확대 수명은 별도 프로세스가 소유한다. 본체가 강제 종료되어도 원래 크기로 복원하고 종료한다.
@MainActor
final class PulseRunner {
    private let cursor: NativeCursor
    private let baseline: Float
    private var lastScale: Float
    private var started = ProcessInfo.processInfo.systemUptime
    private var timer: Timer?
    private var signals: [DispatchSourceSignal] = []

    init?(cursor: NativeCursor) {
        guard let baseline = cursor.scale() else { return nil }
        self.cursor = cursor
        self.baseline = baseline
        self.lastScale = baseline
    }

    func run() {
        for number in [SIGTERM, SIGINT, SIGUSR1] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                if number == SIGUSR1 { self.started = ProcessInfo.processInfo.systemUptime }
                else { self.finish() }
            }
            source.resume()
            signals.append(source)
        }
        update()
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        RunLoop.main.run()
    }

    private func update() {
        // 도중 사용자가 포인터 크기를 바꾸면 그 값을 덮어쓰지 않는다.
        guard let actual = cursor.scale(), abs(actual - lastScale) < 0.02 else { finish(restore: false); return }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        guard elapsed < 0.8 else { finish(); return }
        let progress = min(1, max(0, (elapsed - 0.16) / 0.64))
        let amplitude = Float(pow(1 - progress, 3))
        let enlarged = min(16, max(4, baseline * 3))
        let value = baseline + (enlarged - baseline) * amplitude
        guard cursor.set(value) else { finish(); return }
        lastScale = value
    }

    private func finish(restore: Bool = true) {
        timer?.invalidate()
        if restore { cursor.set(baseline) }
        exit(0)
    }
}
