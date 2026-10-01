import AppKit
import QuartzCore

/// 도착 화면의 둘레만 잠깐 밝힌다. 입력과 활성 앱에는 관여하지 않는다.
@MainActor
final class ScreenEdgeFlash {
    static let duration: TimeInterval = 0.24
    private var panel: EdgeFlashPanel?
    private var dismissal: Task<Void, Never>?

    func show(on displayID: CGDirectDisplayID) {
        stop()
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else { return }

        // CGDisplayID로 NSScreen을 찾은 뒤 AppKit의 전체 frame을 사용한다.
        // visibleFrame은 메뉴바·Dock을 제외하므로 화면 테두리와 맞지 않는다.
        let panel = EdgeFlashPanel(contentRect: screen.frame,
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications,
                                    .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        panel.setAccessibilityElement(false)

        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.setAccessibilityElement(false)
        let root = CALayer()
        root.frame = view.bounds
        root.contentsScale = screen.backingScaleFactor
        root.masksToBounds = true
        view.layer = root
        panel.contentView = view

        // 가는 윤곽선을 그리지 않고 화면 안쪽 64pt에 걸쳐 빛을 부드럽게 흩뜨린다.
        let width = view.bounds.width
        let height = view.bounds.height
        let spread = min(64, min(width, height) * 0.06)
        let blue = NSColor(calibratedRed: 0.3, green: 0.7, blue: 1, alpha: 1)
        let bands: [(CGRect, CGPoint, CGPoint)] = [
            (CGRect(x: 0, y: 0, width: spread, height: height), CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)),
            (CGRect(x: width - spread, y: 0, width: spread, height: height), CGPoint(x: 1, y: 0.5), CGPoint(x: 0, y: 0.5)),
            (CGRect(x: 0, y: 0, width: width, height: spread), CGPoint(x: 0.5, y: 0), CGPoint(x: 0.5, y: 1)),
            (CGRect(x: 0, y: height - spread, width: width, height: spread), CGPoint(x: 0.5, y: 1), CGPoint(x: 0.5, y: 0)),
        ]
        for (frame, start, end) in bands {
            let glow = CAGradientLayer()
            glow.frame = frame
            glow.colors = [0.52, 0.3, 0.08, 0].map { blue.withAlphaComponent($0).cgColor }
            glow.locations = [0, 0.18, 0.55, 1]
            glow.startPoint = start
            glow.endPoint = end
            glow.contentsScale = screen.backingScaleFactor
            root.addSublayer(glow)
        }

        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = reducedMotion ? 0.12 : Self.duration
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.opacity = reducedMotion ? 0.6 : 0
        CATransaction.commit()
        self.panel = panel
        panel.orderFrontRegardless()

        if !reducedMotion {
            let flash = CAKeyframeAnimation(keyPath: "opacity")
            flash.values = [0, 0.9, 0.65, 0]
            flash.keyTimes = [0, 0.17, 0.4, 1]
            flash.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
                                     CAMediaTimingFunction(name: .linear),
                                     CAMediaTimingFunction(name: .easeOut)]
            flash.duration = duration
            root.add(flash, forKey: "arrivalFlash")
        }

        dismissal = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(duration + 0.02)) }
            catch { return }
            self?.stop()
        }
    }

    func stop() {
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }
}

private final class EdgeFlashPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
