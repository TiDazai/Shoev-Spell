import AppKit
import Carbon.HIToolbox

protocol TextInjecting {
    func replace(deleteCount: Int, with replacement: String, trailingEvent: CGEvent?, context: CaretContext) -> Bool
}

final class EventInjector: TextInjecting {
    static let marker: Int64 = 0x5350454C4C
    func replace(deleteCount: Int, with replacement: String, trailingEvent: CGEvent? = nil, context: CaretContext) -> Bool {
        guard !IsSecureEventInputEnabled(),
              let element = context.element,
              let current = CaretContextReader().read(),
              current.matches(context), current.selectionLength == 0,
              var range = TextReplacement.selection(prefix: current.prefix, deleteCount: deleteCount),
              let selection = AXValueCreate(.cfRange, &range) else { return false }
        // Require a writable selected-text API. Never delete first and then
        // emulate the A/Ф key: some controls ignore CGEvent's Unicode payload.
        for attribute in [kAXSelectedTextRangeAttribute, kAXSelectedTextAttribute] {
            var writable: DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(element, attribute as CFString, &writable) == .success,
                  writable.boolValue else { return false }
        }
        let copied = trailingEvent?.copy()
        if trailingEvent != nil && copied == nil { return false }
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, selection) == .success else { return false }
        let selected = CaretContextReader().read()
        guard selected?.sameField(as: current) == true,
              selected?.prefix == String(current.prefix.dropLast(deleteCount)),
              selected?.selectionLength == range.length,
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFString) == .success else {
            var previous = CFRange(location: current.prefix.utf16.count, length: 0)
            if let value = AXValueCreate(.cfRange, &previous) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
            }
            return false
        }
        // Selected-text setters differ between controls: collapse the replacement
        // explicitly before replaying Space/Enter, so it cannot overwrite it.
        var end = CFRange(location: range.location + replacement.utf16.count, length: 0)
        guard let endValue = AXValueCreate(.cfRange, &end),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, endValue) == .success else {
            return true // Text is already replaced; do not replay into a selection.
        }
        if let copied {
            copied.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            copied.post(tap: .cgAnnotatedSessionEventTap)
        }
        return true
    }
}

struct TextReplacement {
    let deleteCount: Int
    let text: String

    static func selection(prefix: String, deleteCount: Int) -> CFRange? {
        guard deleteCount >= 0, deleteCount <= prefix.count else { return nil }
        let removed = prefix.suffix(deleteCount).utf16.count
        return CFRange(location: prefix.utf16.count - removed, length: removed)
    }

    init(original: String, replacement: String) {
        let shared = zip(original, replacement).prefix { $0 == $1 }.count
        deleteCount = original.count - shared
        text = String(replacement.dropFirst(shared))
    }

}
