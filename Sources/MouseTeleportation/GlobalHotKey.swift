import Carbon

@MainActor
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private var pressed = false
    private static let signature: OSType = 0x4D54504C

    init(action: @escaping () -> Void) { self.action = action }

    func start() throws {
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue().receive(event)
            }
        }, events.count, &events, context, &handler)
        guard result == noErr else { throw AppError.message("전역 단축키 핸들러 오류: \(result)") }
        let status = RegisterEventHotKey(UInt32(kVK_Tab), UInt32(optionKey),
            EventHotKeyID(signature: Self.signature, id: 1), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &hotKey)
        guard status == noErr else {
            stop()
            throw AppError.message("Option + Tab 등록 실패 (\(status)). 같은 단축키를 사용하는 다른 앱을 확인하세요.")
        }
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        pressed = false
    }

    private func receive(_ event: EventRef) -> OSStatus {
        var id = EventHotKeyID()
        guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
              id.signature == Self.signature, id.id == 1 else { return OSStatus(eventNotHandledErr) }
        if GetEventKind(event) == UInt32(kEventHotKeyReleased) { pressed = false }
        else if !pressed { pressed = true; action() }
        return noErr
    }
}
