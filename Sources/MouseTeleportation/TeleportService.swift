import AppKit
import TeleportCore

enum AppError: Error, CustomStringConvertible {
    case message(String)
    var description: String { switch self { case .message(let text): text } }
}

func report(_ message: String) {
    FileHandle.standardError.write(Data(("Mouse Teleportation: " + message + "\n").utf8))
}

enum ScreenSnapshot {
    static func displays() throws -> [Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { throw AppError.message("화면 목록을 읽지 못했습니다.") }
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { throw AppError.message("화면 구성이 변경되었습니다. 다시 시도하세요.") }
        return ids.prefix(Int(count)).filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { Display(id: $0, bounds: CGDisplayBounds($0)) }
    }
}

@MainActor
final class TeleportService {
    let pulse = CursorPulse()

    @discardableResult func teleport() throws -> CGPoint? {
        // 드래그 도중 파일이나 선택 영역을 다른 화면으로 끌어가는 부작용을 막는다.
        guard NSEvent.pressedMouseButtons == 0 else { return nil }
        guard let point = CGEvent(source: nil)?.location else { throw AppError.message("포인터 위치를 읽지 못했습니다.") }
        guard let next = DisplayLayout.destination(from: point, displays: try ScreenSnapshot.displays()) else { return nil }
        let destination = next.center
        let result = CGWarpMouseCursorPosition(destination)
        guard result == .success else { throw AppError.message("포인터 이동 실패: \(result.rawValue)") }
        pulse.show()
        return destination
    }
}
