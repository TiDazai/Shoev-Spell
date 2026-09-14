import CoreGraphics

final class EventInjector {
    static let marker: Int64 = 0x5350454C4C
    private let source = CGEventSource(stateID: .combinedSessionState)

    func replace(deleteCount: Int, with replacement: String, trailingEvent: CGEvent? = nil) {
        for _ in 0..<deleteCount {
            postKey(code: 51, down: true)
            postKey(code: 51, down: false)
        }
        postText(replacement)
        if let copied = trailingEvent?.copy() {
            copied.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            copied.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    private func postKey(code: CGKeyCode, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func postText(_ text: String) {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            units.withUnsafeBufferPointer {
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress!)
            }
            event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
