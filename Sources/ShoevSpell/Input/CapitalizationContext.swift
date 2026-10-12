import AppKit
import ApplicationServices

struct CaretContext {
    let prefix: String
    let selectionLength: Int
    var nextCharacter: Character? = nil
    var element: AXUIElement? = nil
    var fullText: String? = nil

    func matches(_ other: CaretContext) -> Bool {
        sameField(as: other) && prefix == other.prefix && selectionLength == other.selectionLength
            && nextCharacter == other.nextCharacter
            && fullText == other.fullText
    }

    func sameField(as other: CaretContext) -> Bool {
        if let element, let otherElement = other.element {
            return CFEqual(element, otherElement)
        }
        return element == nil && other.element == nil
    }

    var startsInsideWord: Bool {
        func isToken(_ character: Character?) -> Bool {
            guard let character else { return false }
            return character.isLetter || character.isNumber || "@#/_\\-'’".contains(character)
        }
        return isToken(prefix.last) || isToken(nextCharacter)
    }
}

enum CapitalizationContext {
    static func shouldCapitalize(after prefix: String) -> Bool {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return true }
        if last == "\n" || last == "\r" { return true }
        if "«„“".contains(last) { return true }
        if last == "\"" {
            // A straight quote after a word is usually a closing quote.
            let before = trimmed.dropLast()
            return before.last?.isLetter != true && before.last?.isNumber != true
        }
        var ending = trimmed
        while let character = ending.last, "»”’\")]}".contains(character) {
            ending.removeLast()
        }
        guard let mark = ending.last, ".!?…".contains(mark) else { return false }
        if mark == "." {
            let token = ending.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
            // Avoid decimals, versions, initials and common abbreviations.
            if token.contains(where: { $0.isNumber }) { return false }
            let abbreviations: Set<String> = ["т.", "д.", "п.", "е.", "г.", "гг.", "ул.", "д-р.", "им.", "рис.", "стр.", "см.", "др.", "пр.", "руб.", "коп.", "тыс.", "млн.", "млрд.", "mr.", "mrs.", "dr.", "etc."]
            if abbreviations.contains(token.lowercased()) { return false }
            if token.count == 2, token.first?.isLetter == true { return false }
            if token.dropLast().contains(".") && !token.hasSuffix("...") { return false }
        }
        return true
    }
}

/// Reads field context for immediate verification; never persists or logs it.
final class CaretContextReader {
    private let access: AccessibilityAccess
    private let diagnostic: (InputDiagnostic) -> Void

    init(access: AccessibilityAccess = AccessibilityAccess(),
         diagnostic: @escaping (InputDiagnostic) -> Void = { InputDiagnostics.shared.record($0) }) {
        self.access = access
        self.diagnostic = diagnostic
    }

    func read() -> CaretContext? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.03)
        guard let focused = access.copy(system, kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { diagnostic(.missingFocus); return nil }
        return read(focusedElement: focused as! AXUIElement)
    }

    func read(focusedElement: AXUIElement) -> CaretContext? {
        var element = focusedElement
        var failure = InputDiagnostic.missingRange
        let deadline = ProcessInfo.processInfo.systemUptime + 0.075
        // Web editors may focus a child inside the editable field. Stay within
        // its nearest text-control ancestors; never search a whole document.
        for depth in 0..<4 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            AXUIElementSetMessagingTimeout(element, 0.03)
            if access.copy(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole {
                diagnostic(.secureField); return nil
            }
            let role = access.copy(element, kAXRoleAttribute) as? String
            if depth == 0 || role == kAXTextFieldRole || role == kAXTextAreaRole {
                if let rawRange = access.copy(element, kAXSelectedTextRangeAttribute),
                   CFGetTypeID(rawRange) == AXValueGetTypeID() {
                    var range = CFRange()
                    if AXValueGetValue(rawRange as! AXValue, .cfRange, &range) {
                        guard let text = access.copy(element, kAXValueAttribute) as? String else {
                            diagnostic(.missingValue); return nil
                        }
                        guard let context = Self.context(element: element, text: text, range: range) else {
                            diagnostic(.invalidRange); return nil
                        }
                        return context
                    }
                    failure = .invalidRange
                }
            }
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  let parent = access.copy(element, kAXParentAttribute),
                  CFGetTypeID(parent) == AXUIElementGetTypeID(), !CFEqual(parent, element) else { break }
            element = parent as! AXUIElement
        }
        diagnostic(failure)
        return nil
    }

    static func context(element: AXUIElement, text: String, range: CFRange) -> CaretContext? {
        let nsText = text as NSString
        guard range.location >= 0, range.length >= 0, range.location <= nsText.length,
              range.length <= nsText.length - range.location else { return nil }
        return CaretContext(
            prefix: nsText.substring(to: range.location),
            selectionLength: range.length,
            nextCharacter: nsText.substring(from: range.location + range.length).first,
            element: element,
            fullText: text
        )
    }
}
