import AppKit
import ServiceManagement
import TeleportCore

@MainActor
func loginStatus() -> String {
    switch SMAppService.mainApp.status {
    case .enabled: "enabled"
    case .notRegistered: "not-registered"
    case .requiresApproval: "requires-approval"
    case .notFound: "not-found"
    @unknown default: "unknown"
    }
}

@MainActor
func enableLogin() throws {
    if SMAppService.mainApp.status == .notRegistered || SMAppService.mainApp.status == .notFound {
        do { try SMAppService.mainApp.register() }
        catch {
            // 최초 실행과 설치 명령이 겹쳐 이미 등록된 경우는 성공으로 처리한다.
            if SMAppService.mainApp.status != .enabled { throw error }
        }
    }
    guard SMAppService.mainApp.status == .enabled else {
        throw AppError.message("로그인 항목 상태: \(loginStatus()). 시스템 설정 → 일반 → 로그인 항목 및 확장 프로그램에서 허용하세요.")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let service = TeleportService()
    private var shortcut: GlobalHotKey?
    private var signalSources: [DispatchSourceSignal] = []
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let shortcut = GlobalHotKey { [weak self] in
                do { try self?.service.teleport() } catch { report(String(describing: error)) }
            }
            try shortcut.start()
            self.shortcut = shortcut
        } catch { report(String(describing: error)); exit(1) }

        // 최초 실행에만 등록한다. 사용자가 시스템 설정에서 끈 로그인 항목은 되살리지 않는다.
        if !UserDefaults.standard.bool(forKey: "didConfigureLogin") {
            do {
                try enableLogin()
                UserDefaults.standard.set(true, forKey: "didConfigureLogin")
            } catch { report(String(describing: error)) }
        }
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.service.stopEffects() }
            })
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcut?.stop()
        service.stopEffects()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

let arguments = Set(CommandLine.arguments.dropFirst())

do {
    // 커서 helper에는 창·앱 이벤트 루프가 필요 없다. NSApplication 초기화 전에 실행한다.
    if arguments.contains("--cursor-pulse") {
        guard let cursor = NativeCursor(), let runner = PulseRunner(cursor: cursor) else { throw AppError.message("시스템 커서 확대 API를 사용할 수 없습니다.") }
        runner.run()
        exit(0)
    }
    let app = NSApplication.shared
    // 비활성 패널을 그리는 본체만 accessory로 실행한다. Dock·메뉴바 항목은 만들지 않는다.
    app.setActivationPolicy(arguments.isEmpty || arguments.contains("--teleport-once") ? .accessory : .prohibited)

    if arguments.contains("--status") || arguments.contains("--self-test") {
        let displays = try ScreenSnapshot.displays()
        let position = CGEvent(source: nil)?.location ?? .zero
        let displayFocus = NativeDisplayFocus()
        let info: [String: Any] = [
            "bundleID": Bundle.main.bundleIdentifier ?? "unbundled",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "development",
            "agentApp": Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool ?? false,
            "loginItem": loginStatus(),
            "cursorScale": NativeCursor()?.scale() as Any? ?? NSNull(),
            "displayFocusAvailable": displayFocus != nil,
            "activeMenuBarDisplay": displayFocus?.activeDisplayID() as Any? ?? NSNull(),
            "cursor": ["x": position.x, "y": position.y],
            "displays": displays.map { ["id": $0.id, "x": $0.bounds.minX, "y": $0.bounds.minY, "width": $0.bounds.width, "height": $0.bounds.height] as [String: Any] },
        ]
        let data = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        if arguments.contains("--self-test") {
            guard Bundle.main.bundleIdentifier == "net.jeonghyeon.MouseTeleportation",
                  Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true,
                  NativeCursor()?.scale() != nil else { exit(1) }
        }
    } else if arguments.contains("--enable-login") {
        try enableLogin()
        UserDefaults.standard.set(true, forKey: "didConfigureLogin")
        print(loginStatus())
    } else if arguments.contains("--disable-login") {
        if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
        UserDefaults.standard.set(true, forKey: "didConfigureLogin")
        print(loginStatus())
    } else if arguments.contains("--teleport-once") {
        let service = TeleportService()
        if let point = try service.teleport() {
            print("Moved to \(point.x), \(point.y)")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: ScreenEdgeFlash.duration + 0.05))
        }
        else { print("No movement: one display or mouse button held.") }
    } else if !arguments.isEmpty {
        print("Mouse Teleportation: --status | --self-test | --enable-login | --disable-login | --teleport-once")
        exit(arguments == ["--help"] ? 0 : 64)
    } else {
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
} catch { report(String(describing: error)); exit(1) }
