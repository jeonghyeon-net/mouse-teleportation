import AppKit
import Darwin
import IOKit

/// 메뉴 막대가 선명하게 표시되는 활성 디스플레이를 변경한다. 개별 창 활성화 API나 클릭은 사용하지 않는다.
/// SkyLight 비공개 API가 없으면 커서 이동과 도착 효과는 그대로 유지한다.
final class NativeDisplayFocus {
    private typealias Connection = @convention(c) () -> Int32
    private typealias CopyDisplay = @convention(c) (Int32) -> Unmanaged<CFString>?
    private typealias SetDisplay = @convention(c) (Int32, CFString, UInt64) -> Void
    private typealias Timestamp = @convention(c) () -> UInt64
    private let handle: UnsafeMutableRawPointer
    private let connection: Connection
    private let copyDisplay: CopyDisplay
    private let setDisplay: SetDisplay
    private let timestamp: Timestamp

    init?() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW | RTLD_LOCAL) else { return nil }
        guard let connection = dlsym(handle, "SLSMainConnectionID"),
              let copyDisplay = dlsym(handle, "SLSCopyActiveMenuBarDisplayIdentifier"),
              let setDisplay = dlsym(handle, "SLSSetActiveMenuBarDisplayIdentifier"),
              let timestamp = dlsym(handle, "SLSCurrentEventTimestamp") else {
            dlclose(handle)
            return nil
        }
        self.handle = handle
        self.connection = unsafeBitCast(connection, to: Connection.self)
        self.copyDisplay = unsafeBitCast(copyDisplay, to: CopyDisplay.self)
        self.setDisplay = unsafeBitCast(setDisplay, to: SetDisplay.self)
        self.timestamp = unsafeBitCast(timestamp, to: Timestamp.self)
    }

    deinit { dlclose(handle) }

    func activeDisplayID() -> CGDirectDisplayID? {
        guard let identifier = copyDisplay(connection())?.takeRetainedValue(),
              let uuid = CFUUIDCreateFromString(nil, identifier) else { return nil }
        let display = CGDisplayGetDisplayIDFromUUID(uuid)
        return display == kCGNullDirectDisplay ? nil : display
    }

    @discardableResult func activate(_ display: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsActive(display) != 0,
              let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
              let identifier = CFUUIDCreateString(nil, uuid) else { return false }
        // 세 번째 인자는 UUID가 아니라 이벤트 시각이다. 오래된 값은 서버가 무시한다.
        // 반환값 대신 WindowServer의 실제 활성 디스플레이를 읽어 적용 여부를 확인한다.
        setDisplay(connection(), identifier, timestamp())
        return activeDisplayID() == display
    }
}
