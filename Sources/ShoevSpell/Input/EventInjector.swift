import AppKit
import Carbon.HIToolbox

protocol TextInjecting {
    func replace(deleteCount: Int, with replacement: String, trailingEvent: CGEvent?, context: CaretContext) -> Bool
}

final class EventInjector: TextInjecting {
    static let marker: Int64 = 0x5350454C4C
    private let access: AccessibilityAccess
    private let readCaret: () -> CaretContext?
    private let secureInput: () -> Bool
    private let diagnostic: (InputDiagnostic) -> Void

    init(access: AccessibilityAccess = AccessibilityAccess(),
         readCaret: @escaping () -> CaretContext? = { CaretContextReader().read() },
         secureInput: @escaping () -> Bool = { IsSecureEventInputEnabled() },
         diagnostic: @escaping (InputDiagnostic) -> Void = { InputDiagnostics.shared.record($0) }) {
        self.access = access
        self.readCaret = readCaret
        self.secureInput = secureInput
        self.diagnostic = diagnostic
    }

    func replace(deleteCount: Int, with replacement: String, trailingEvent: CGEvent? = nil, context: CaretContext) -> Bool {
        guard !secureInput() else { diagnostic(.secureField); return false }
        guard let element = context.element,
              let current = readCaret(),
              current.matches(context), current.selectionLength == 0,
              let originalText = current.fullText,
              var range = TextReplacement.selection(prefix: current.prefix, deleteCount: deleteCount),
              let selection = AXValueCreate(.cfRange, &range) else { diagnostic(.contextChanged); return false }
        // Space and punctuation belong in the same edit as the corrected text.
        // This preserves the delimiter even if collapsing the caret fails.
        let inlineDelimiter = trailingEvent.flatMap(Self.inlineDelimiter)
        guard trailingEvent == nil || inlineDelimiter != nil else { return false }
        let insertedText = replacement + (inlineDelimiter ?? "")
        let expectedText = (originalText as NSString).replacingCharacters(
            in: NSRange(location: range.location, length: range.length), with: insertedText)
        guard access.writable(element, kAXSelectedTextRangeAttribute) else {
            diagnostic(.selectionReadOnly); return false
        }
        let method: InputDiagnostic
        if access.writable(element, kAXSelectedTextAttribute) {
            method = .correctedSelection
        } else if access.parameterNames(element).contains("AXTextOperation") {
            method = .correctedMarker
        } else if Self.canReplaceWholeValue(text: originalText,
                     role: access.copy(element, kAXRoleAttribute) as? String,
                     childrenCount: (access.copy(element, kAXChildrenAttribute) as? [Any])?.count),
                  access.writable(element, kAXValueAttribute) {
            method = .correctedValue
        } else { diagnostic(.replacementUnsupported); return false }

        // Capability checks may query another process. Validate again before
        // any mutation; never replace an entire rich document as a fallback.
        guard readCaret()?.matches(current) == true else { diagnostic(.contextChanged); return false }
        if method == .correctedValue {
            guard access.set(element, kAXValueAttribute, expectedText as CFString) == .success else {
                guard let failed = readCaret(), failed.matches(current) else {
                    diagnostic(.replacementUnverified); return true
                }
                diagnostic(.replacementFailed); return false
            }
        } else {
            guard access.set(element, kAXSelectedTextRangeAttribute, selection) == .success else {
                diagnostic(.selectionReadOnly); return false
            }
            guard let selected = selectedContext(current: current, deleteCount: deleteCount, length: range.length) else {
                diagnostic(.selectionPending)
                return !restoreCaret(current)
            }
            let success: Bool
            if method == .correctedMarker {
                // Opaque markers stay local to the editor. Validate their exact
                // text before using AXTextOperation; never infer global offsets.
                if let markers = access.copy(element, "AXSelectedTextMarkerRange"),
                   access.parameter(element, "AXStringForTextMarkerRange", markers) as? String == String(current.prefix.suffix(deleteCount)),
                   readCaret()?.matches(selected) == true {
                    let arguments: NSDictionary = [
                        "AXTextOperationType": "TextOperationReplacePreserveCase",
                        "AXTextOperationMarkerRanges": [markers],
                        "AXTextOperationReplacementString": insertedText
                    ]
                    success = (access.parameter(element, "AXTextOperation", arguments) as? [String]) == [insertedText]
                } else { success = false }
            } else {
                success = access.set(element, kAXSelectedTextAttribute, insertedText as CFString) == .success
            }
            if !success {
                // A failing setter may still have edited: never blindly restore
                // or let a delimiter overwrite its result.
                guard let failed = readCaret(), failed.sameField(as: current), failed.fullText == originalText else {
                    diagnostic(.replacementUnverified); return true
                }
                diagnostic(.replacementFailed)
                return !restoreCaret(current)
            }
        }
        guard let after = replacementContext(current: current, expectedText: expectedText), after.sameField(as: current) else {
            diagnostic(.replacementUnverified)
            return true // Never replay or restore into another field.
        }
        if TextReplacement.wasIgnored(before: originalText, expected: expectedText, after: after.fullText) {
            // A successful AX status is not proof of an edit. Restore the caret
            // before allowing the original delimiter to reach the editor.
            diagnostic(.replacementIgnored)
            return !restoreCaret(current)
        }
        guard after.fullText == expectedText else { diagnostic(.replacementUnverified); return true }
        var end = CFRange(location: range.location + insertedText.utf16.count, length: 0)
        guard let endValue = AXValueCreate(.cfRange, &end),
              access.set(element, kAXSelectedTextRangeAttribute, endValue) == .success else {
            diagnostic(.replacementUnverified)
            return true // Text is already replaced; do not replay into a selection.
        }
        diagnostic(method)
        return true
    }

    private func restoreCaret(_ original: CaretContext) -> Bool {
        guard let element = original.element, let now = readCaret(),
              now.sameField(as: original), now.fullText == original.fullText else { return false }
        var range = CFRange(location: original.prefix.utf16.count, length: 0)
        guard let value = AXValueCreate(.cfRange, &range),
              access.set(element, kAXSelectedTextRangeAttribute, value) == .success,
              let restored = readCaret(), restored.matches(original) else { return false }
        return true
    }

    private func selectedContext(current: CaretContext, deleteCount: Int, length: Int) -> CaretContext? {
        // Web editors acknowledge an AX request before the renderer publishes
        // the new range. Retry only the unchanged original state, at most twice.
        // Different text/focus is never treated as merely delayed.
        for attempt in 0..<3 {
            guard let selected = readCaret(), selected.sameField(as: current),
                  selected.fullText == current.fullText else { return nil }
            if selected.prefix == String(current.prefix.dropLast(deleteCount)),
               selected.selectionLength == length, selected.nextCharacter == current.nextCharacter {
                return selected
            }
            guard selected.matches(current), attempt < 2 else { return nil }
            Thread.sleep(forTimeInterval: 0.002)
        }
        return nil
    }

    private func replacementContext(current: CaretContext, expectedText: String) -> CaretContext? {
        for attempt in 0..<3 {
            guard let after = readCaret() else { return nil }
            if !after.sameField(as: current) || after.fullText == expectedText || after.fullText != current.fullText {
                return after
            }
            if attempt == 2 { return after }
            Thread.sleep(forTimeInterval: 0.002)
        }
        return nil
    }

    static func canReplaceWholeValue(text: String, role: String?, childrenCount: Int?) -> Bool {
        // Only small, leaf text controls. A contenteditable tree with paragraphs,
        // attachments or formatting is never flattened into an AXValue string.
        text.utf16.count <= 16_384 && childrenCount == 0
            && (role == kAXTextFieldRole || role == kAXTextAreaRole)
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
