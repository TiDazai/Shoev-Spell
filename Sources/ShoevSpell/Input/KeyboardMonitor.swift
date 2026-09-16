import Carbon.HIToolbox
import AppKit
import CoreGraphics
import Foundation
import OSLog

protocol KeyboardMonitorDelegate: AnyObject {
    func monitorDidReset(_ monitor: KeyboardMonitor)
    func monitor(_ monitor: KeyboardMonitor, keyDown event: CGEvent, text: String, keyCode: CGKeyCode) -> Bool
}

final class KeyboardMonitor {
    private let logger = Logger(subsystem: "com.shoev.spell", category: "monitor")
    weak var delegate: KeyboardMonitorDelegate?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func requestPermissions() -> Bool {
        let canListen = CGPreflightListenEventAccess() || CGRequestListenEventAccess()
        let canPost = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
        return canListen && canPost
    }

    func openMissingPermissionSettings() {
        let anchor: String
        if !CGPreflightListenEventAccess() {
            anchor = "Privacy_ListenEvent"
        } else if !CGPreflightPostEventAccess() {
            anchor = "Privacy_Accessibility"
        } else {
            return
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: spellKeyboardCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Event tap creation failed; listenPermission=\(CGPreflightListenEventAccess()), postPermission=\(CGPreflightPostEventAccess())")
            return false
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        tap = created
        source = runLoopSource
        timer = .scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let tap = self?.tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        logger.info("Event tap started; listenPermission=\(CGPreflightListenEventAccess()), postPermission=\(CGPreflightPostEventAccess())")
        return true
    }

    func stop() {
        timer?.invalidate()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        timer = nil
        source = nil
        tap = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            delegate?.monitorDidReset(self)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == EventInjector.marker {
            return Unmanaged.passUnretained(event)
        }
        // Shoev Switcher replaces text independently; its synthetic events must
        // invalidate our old phrase, not become a new spelling candidate.
        if event.getIntegerValueField(.eventSourceUserData) == 0x53484F4556 {
            delegate?.monitorDidReset(self)
            return Unmanaged.passUnretained(event)
        }
        if IsSecureEventInputEnabled() {
            delegate?.monitorDidReset(self)
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else {
            delegate?.monitorDidReset(self)
            return Unmanaged.passUnretained(event)
        }
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)
        guard length <= buffer.count else {
            delegate?.monitorDidReset(self)
            return Unmanaged.passUnretained(event)
        }
        let text = length > 0 ? String(utf16CodeUnits: buffer, count: length) : ""
        return delegate?.monitor(self, keyDown: event, text: text, keyCode: code) == true
            ? nil
            : Unmanaged.passUnretained(event)
    }
}

private let spellKeyboardCallback: CGEventTapCallBack = { _, type, event, pointer in
    guard let pointer else { return Unmanaged.passUnretained(event) }
    return Unmanaged<KeyboardMonitor>.fromOpaque(pointer).takeUnretainedValue().handle(type: type, event: event)
}
