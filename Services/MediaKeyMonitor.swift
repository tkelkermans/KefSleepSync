import AppKit
import CoreGraphics
import IOKit.hidsystem

enum MediaKeyAction: String, Equatable {
    case volumeUp
    case volumeDown

    var displayName: String {
        switch self {
        case .volumeUp:
            return "Volume Up"
        case .volumeDown:
            return "Volume Down"
        }
    }

    static func fromSystemDefinedEvent(subtype: Int, data1: Int32) -> MediaKeyAction? {
        guard subtype == Int(NX_SUBTYPE_AUX_CONTROL_BUTTONS) else {
            return nil
        }

        let rawData = UInt32(bitPattern: data1)
        let keyCode = Int((rawData & 0xFFFF_0000) >> 16)
        let keyFlags = Int(rawData & 0x0000_FFFF)
        let keyState = (keyFlags & 0xFF00) >> 8

        // Only react on key-down style events so key-up does not trigger a second adjustment.
        guard keyState == 0xA else {
            return nil
        }

        switch keyCode {
        case Int(NX_KEYTYPE_SOUND_UP):
            return .volumeUp
        case Int(NX_KEYTYPE_SOUND_DOWN):
            return .volumeDown
        default:
            return nil
        }
    }
}

final class MediaKeyMonitor {
    typealias Handler = (MediaKeyAction) -> Bool

    var onMediaKey: Handler?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    deinit {
        stop()
    }

    var isRunning: Bool {
        eventTap != nil
    }

    func hasPermission() -> Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    func requestPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    func start() {
        guard eventTap == nil else { return }
        guard hasPermission() else {
            AppLogger.keyboard.notice("Media key monitor did not start because Input Monitoring permission is missing.")
            return
        }

        let eventMask = CGEventMask(1 << UInt64(NX_SYSDEFINED))
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            AppLogger.keyboard.error("Failed to create the media key event tap.")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource

        AppLogger.keyboard.info("Started the media key event tap.")
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
            AppLogger.keyboard.info("Stopped the media key event tap.")
        }
    }

    private func handleEvent(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                AppLogger.keyboard.notice("Re-enabled the media key event tap after a timeout or user input disable.")
            }
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        guard type.rawValue == NX_SYSDEFINED else {
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event),
              let action = MediaKeyAction.fromSystemDefinedEvent(
                  subtype: Int(nsEvent.subtype.rawValue),
                  data1: Int32(truncatingIfNeeded: nsEvent.data1)
              ) else {
            return Unmanaged.passUnretained(event)
        }

        let shouldSuppress = onMediaKey?(action) ?? false
        if shouldSuppress {
            AppLogger.keyboard.debug("Suppressed \(action.displayName, privacy: .public).")
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}
