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
              let originalText = current.fullText,
              var range = TextReplacement.selection(prefix: current.prefix, deleteCount: deleteCount),
              let selection = AXValueCreate(.cfRange, &range) else { return false }
        // Require a writable selected-text API. Never delete first and then
        // emulate the A/Ф key: some controls ignore CGEvent's Unicode payload.
        for attribute in [kAXSelectedTextRangeAttribute, kAXSelectedTextAttribute] {
            var writable: DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(element, attribute as CFString, &writable) == .success,
                  writable.boolValue else { return false }
        }
        // Space and punctuation belong in the same edit as the corrected text.
        // This preserves the delimiter even if collapsing the caret fails.
        let inlineDelimiter = trailingEvent.flatMap(Self.inlineDelimiter)
        guard trailingEvent == nil || inlineDelimiter != nil else { return false }
        let insertedText = replacement + (inlineDelimiter ?? "")
        let expectedText = (originalText as NSString).replacingCharacters(
            in: NSRange(location: range.location, length: range.length), with: insertedText)
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, selection) == .success else { return false }
        let selected = CaretContextReader().read()
        guard selected?.sameField(as: current) == true,
              selected?.prefix == String(current.prefix.dropLast(deleteCount)),
              selected?.selectionLength == range.length,
              selected?.nextCharacter == current.nextCharacter,
              selected?.fullText == originalText,
              AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, insertedText as CFString) == .success else {
            var previous = CFRange(location: current.prefix.utf16.count, length: 0)
            if let value = AXValueCreate(.cfRange, &previous) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
            }
            return false
        }
        // Selected-text setters differ between controls: collapse the replacement
        // explicitly before replaying Space/Enter, so it cannot overwrite it.
        guard let after = CaretContextReader().read(), after.sameField(as: current) else {
            return true // The edit succeeded; never replay a key into another field.
        }
        if TextReplacement.wasIgnored(before: originalText, expected: expectedText, after: after.fullText) {
            // A successful AX status is not proof of an edit. Restore the caret
            // before allowing the original delimiter to reach the editor.
            var previous = CFRange(location: current.prefix.utf16.count, length: 0)
            guard let value = AXValueCreate(.cfRange, &previous),
                  AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
                return true // Do not let the delimiter overwrite the selection.
            }
            return false
        }
        guard after.fullText == expectedText else { return true }
        var end = CFRange(location: range.location + insertedText.utf16.count, length: 0)
        guard let endValue = AXValueCreate(.cfRange, &end),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, endValue) == .success else {
            return true // Text is already replaced; do not replay into a selection.
        }
        return true
    }

    static func inlineDelimiter(_ event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0, length <= buffer.count else { return nil }
        let text = String(utf16CodeUnits: buffer, count: length)
        return text.unicodeScalars.allSatisfy { CharacterSet(charactersIn: " ,.;:!?…").contains($0) } ? text : nil
    }
}

struct TextReplacement {
    let deleteCount: Int
    let text: String

    static func wasIgnored(before: String, expected: String, after: String?) -> Bool {
        before != expected && after == before
    }

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
