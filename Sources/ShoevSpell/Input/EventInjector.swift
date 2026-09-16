import CoreGraphics

protocol TextInjecting {
    func replace(deleteCount: Int, with replacement: String, trailingEvent: CGEvent?)
}

final class EventInjector: TextInjecting {
    static let marker: Int64 = 0x5350454C4C
    private let source = CGEventSource(stateID: .combinedSessionState)

    func replace(deleteCount: Int, with replacement: String, trailingEvent: CGEvent? = nil) {
        guard deleteCount >= 0 else { return }
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
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func postText(_ text: String) {
        for units in TextReplacement.unicodeChunks(text) {
          for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            units.withUnsafeBufferPointer {
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress!)
            }
            event.post(tap: .cgAnnotatedSessionEventTap)
          }
        }
    }
}

struct TextReplacement {
    let deleteCount: Int
    let text: String

    init(original: String, replacement: String) {
        let shared = zip(original, replacement).prefix { $0 == $1 }.count
        deleteCount = original.count - shared
        text = String(replacement.dropFirst(shared))
    }

    /// CGEvent accepts at most 20 UTF-16 units per event. Never split a scalar.
    static func unicodeChunks(_ text: String) -> [[UInt16]] {
        var result: [[UInt16]] = []
        var chunk: [UInt16] = []
        for scalar in text.unicodeScalars {
            let units = Array(String(scalar).utf16)
            if chunk.count + units.count > 20 {
                result.append(chunk)
                chunk = []
            }
            chunk.append(contentsOf: units)
        }
        if !chunk.isEmpty { result.append(chunk) }
        return result
    }
}
