import AppKit
import ApplicationServices

struct CaretContext {
    let prefix: String
    let selectionLength: Int
    var nextCharacter: Character? = nil

    var startsInsideWord: Bool { prefix.last?.isLetter == true || nextCharacter?.isLetter == true }
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

/// Reads only the text preceding the selection; never stores or logs field contents.
final class CaretContextReader {
    func read() -> CaretContext? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.03)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.03)
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if subrole as? String == kAXSecureTextFieldSubrole as String { return nil }
        var rawRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rawRange) == .success,
              let rawRange, CFGetTypeID(rawRange) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rawRange as! AXValue, .cfRange, &range), range.location >= 0 else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        let nsText = text as NSString
        guard range.length >= 0, range.location <= nsText.length,
              range.length <= nsText.length - range.location else { return nil }
        return CaretContext(
            prefix: nsText.substring(to: range.location),
            selectionLength: range.length,
            nextCharacter: nsText.substring(from: range.location + range.length).first
        )
    }
}
