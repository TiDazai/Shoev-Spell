import AppKit
import XCTest
@testable import ShoevSpell

final class AccessibilityReplacementTests: XCTestCase {
    func testLeafValueFallbackWorksWithoutWritableSelectedText() {
        let editor = FakeTextControl()
        XCTAssertTrue(editor.replace())
        XCTAssertEqual(editor.text, "🐈 я привет ")
        XCTAssertEqual(editor.range.length, 0)
        XCTAssertEqual(editor.range.location, editor.text.utf16.count)
        XCTAssertEqual(editor.reasons.last, .correctedValue)
        XCTAssertFalse(editor.writes.contains(kAXSelectedTextAttribute))
    }

    func testNativeSelectedTextRemainsPreferred() {
        let editor = FakeTextControl()
        editor.supportsSelectedText = true
        editor.supportsMarkers = true
        XCTAssertTrue(editor.replace())
        XCTAssertEqual(editor.text, "🐈 я привет ")
        XCTAssertEqual(editor.reasons.last, .correctedSelection)
        XCTAssertFalse(editor.writes.contains(kAXValueAttribute))
    }

    func testDelayedWebSelectionIsConfirmedBeforeReplacingText() {
        let editor = FakeTextControl()
        editor.supportsSelectedText = true
        editor.selectionDelayReads = 2
        XCTAssertTrue(editor.replace())
        XCTAssertEqual(editor.text, "🐈 я привет ")
        XCTAssertEqual(editor.reasons.last, .correctedSelection)
    }

    func testMarkerReplacementPreservesExplicitCase() {
        let editor = FakeTextControl()
        editor.supportsMarkers = true
        editor.children = 2 // Rich editor: whole-value replacement is prohibited.
        XCTAssertTrue(editor.replace(with: "ИВЕТ"))
        XCTAssertEqual(editor.text, "🐈 я прИВЕТ ")
        XCTAssertEqual(editor.operationType, "TextOperationReplacePreserveCase")
        XCTAssertEqual(editor.reasons.last, .correctedMarker)
        XCTAssertFalse(editor.writes.contains(kAXValueAttribute))
    }

    func testMarkersMustDescribeTheExactSelectedText() {
        let editor = FakeTextControl()
        editor.supportsMarkers = true
        editor.markerTextOverride = "другое слово"
        XCTAssertFalse(editor.replace())
        XCTAssertEqual(editor.text, "🐈 я превет")
        XCTAssertNil(editor.operationType)
        XCTAssertEqual(editor.range.length, 0)
        XCTAssertEqual(editor.reasons.last, .replacementFailed)
    }

    func testRichValueIsNeverFlattened() {
        let editor = FakeTextControl()
        editor.children = 1
        XCTAssertFalse(editor.replace())
        XCTAssertTrue(editor.writes.isEmpty)
        XCTAssertEqual(editor.reasons.last, .replacementUnsupported)
    }

    func testMissingChildInformationIsNotAssumedToBePlainText() {
        XCTAssertFalse(EventInjector.canReplaceWholeValue(text: "превет", role: kAXTextAreaRole, childrenCount: nil))
        XCTAssertFalse(EventInjector.canReplaceWholeValue(text: "превет", role: "AXWebArea", childrenCount: 0))
        XCTAssertFalse(EventInjector.canReplaceWholeValue(text: String(repeating: "а", count: 16_385), role: kAXTextAreaRole, childrenCount: 0))
    }

    func testReadOnlySelectionDoesNotWriteValue() {
        let editor = FakeTextControl()
        editor.supportsSelection = false
        XCTAssertFalse(editor.replace())
        XCTAssertTrue(editor.writes.isEmpty)
        XCTAssertEqual(editor.reasons.last, .selectionReadOnly)
    }

    func testIgnoredValueSetterPreservesOriginalDelimiter() {
        let editor = FakeTextControl()
        editor.ignoreReplacement = true
        XCTAssertFalse(editor.replace())
        XCTAssertEqual(editor.text, "🐈 я превет")
        XCTAssertEqual(editor.range.length, 0)
        XCTAssertEqual(editor.reasons.last, .replacementIgnored)
    }

    func testIgnoredSelectedTextSetterRestoresTheOriginalCaret() {
        let editor = FakeTextControl()
        editor.supportsSelectedText = true
        editor.ignoreReplacement = true
        XCTAssertFalse(editor.replace())
        XCTAssertEqual(editor.text, "🐈 я превет")
        XCTAssertEqual(editor.range.location, editor.text.utf16.count)
        XCTAssertEqual(editor.range.length, 0)
    }

    func testChangedFocusBeforeMutationIsSkipped() {
        let editor = FakeTextControl()
        editor.changeFocusOnRead = 2
        XCTAssertFalse(editor.replace())
        XCTAssertTrue(editor.writes.isEmpty)
        XCTAssertEqual(editor.reasons.last, .contextChanged)
    }

    func testSecureInputNeverWrites() {
        let editor = FakeTextControl()
        editor.secure = true
        XCTAssertFalse(editor.replace())
        XCTAssertTrue(editor.writes.isEmpty)
        XCTAssertEqual(editor.reasons.last, .secureField)
    }

    func testEnterIsRejectedBeforeAnyMutation() {
        let editor = FakeTextControl()
        XCTAssertFalse(editor.replace(delimiter: "\r"))
        XCTAssertTrue(editor.writes.isEmpty)
    }

    func testFocusedChildResolvesOnlyItsNearestTextAncestor() {
        let editor = FakeTextControl()
        let child = AXUIElementCreateApplication(999_992)
        var access = editor.access
        let originalCopy = access.copy
        access.copy = { element, attribute in
            if CFEqual(element, child) {
                if attribute == kAXRoleAttribute { return kAXStaticTextRole as CFString }
                if attribute == kAXParentAttribute { return editor.element }
                return nil
            }
            return originalCopy(element, attribute)
        }
        let reader = CaretContextReader(access: access)
        XCTAssertTrue(reader.read(focusedElement: child)?.sameField(as: editor.context) == true)
    }

    func testSecureFocusedChildCannotEscapeIntoItsParent() {
        let editor = FakeTextControl()
        var access = editor.access
        let originalCopy = access.copy
        access.copy = { element, attribute in
            if attribute == kAXSubroleAttribute { return kAXSecureTextFieldSubrole as CFString }
            return originalCopy(element, attribute)
        }
        var reasons: [InputDiagnostic] = []
        let reader = CaretContextReader(access: access, diagnostic: { reasons.append($0) })
        XCTAssertNil(reader.read(focusedElement: editor.element))
        XCTAssertEqual(reasons, [.secureField])
    }

    func testInvalidAndOutOfBoundsRangesAreRejected() {
        let element = AXUIElementCreateApplication(999_991)
        for range in [CFRange(location: -1, length: 0), CFRange(location: 99, length: 0),
                      CFRange(location: 2, length: -1), CFRange(location: 2, length: Int.max)] {
            XCTAssertNil(CaretContextReader.context(element: element, text: "abc", range: range))
        }
    }

    func testParentTraversalHasABoundedDepth() {
        let element = AXUIElementCreateApplication(999_991)
        let other = AXUIElementCreateApplication(999_992)
        var parentReads = 0
        var access = AccessibilityAccess()
        access.copy = { current, name in
            if name == kAXParentAttribute {
                parentReads += 1
                return CFEqual(current, element) ? other : element
            }
            return nil
        }
        let reader = CaretContextReader(access: access, diagnostic: { _ in })
        XCTAssertNil(reader.read(focusedElement: element))
        XCTAssertLessThanOrEqual(parentReads, 4)
    }
}

private final class FakeTextControl {
    let element = AXUIElementCreateApplication(999_991)
    var text = "🐈 я превет"
    var range = CFRange(location: "🐈 я превет".utf16.count, length: 0)
    var children = 0
    var supportsSelection = true
    var supportsSelectedText = false
    var supportsMarkers = false
    var ignoreReplacement = false
    var secure = false
    var markerTextOverride: String?
    var operationType: String?
    var writes: [String] = []
    var reasons: [InputDiagnostic] = []
    var changeFocusOnRead: Int?
    var reads = 0
    var selectionDelayReads = 0
    var pendingSelection: CFRange?
    var pendingReads = 0

    var context: CaretContext {
        CaretContextReader.context(element: element, text: text, range: range)!
    }

    var access: AccessibilityAccess {
        var access = AccessibilityAccess()
        access.copy = { [unowned self] _, name in
            switch name {
            case kAXRoleAttribute: return kAXTextAreaRole as CFString
            case kAXChildrenAttribute: return Array(repeating: "child", count: children) as CFArray
            case kAXSelectedTextRangeAttribute:
                var selected = range
                return AXValueCreate(.cfRange, &selected)
            case kAXValueAttribute: return text as CFString
            case "AXSelectedTextMarkerRange": return "opaque-marker" as CFString
            default: return nil
            }
        }
        access.writable = { [unowned self] _, name in
            switch name {
            case kAXSelectedTextRangeAttribute: return supportsSelection
            case kAXSelectedTextAttribute: return supportsSelectedText
            case kAXValueAttribute: return true
            default: return false
            }
        }
        access.parameterNames = { [unowned self] _ in supportsMarkers ? ["AXTextOperation"] : [] }
        access.parameter = { [unowned self] _, name, argument in
            if name == "AXStringForTextMarkerRange" {
                return (markerTextOverride ?? (text as NSString).substring(with: NSRange(location: range.location, length: range.length))) as CFString
            }
            if name == "AXTextOperation", let dict = argument as? NSDictionary,
               let replacement = dict["AXTextOperationReplacementString"] as? String {
                operationType = dict["AXTextOperationType"] as? String
                applySelection(replacement)
                return [replacement] as CFArray
            }
            return nil
        }
        access.set = { [unowned self] _, name, argument in
            writes.append(name)
            if name == kAXSelectedTextRangeAttribute {
                var selected = CFRange()
                guard AXValueGetValue(argument as! AXValue, .cfRange, &selected) else { return .illegalArgument }
                if selected.length > 0 && selectionDelayReads > 0 {
                    pendingSelection = selected
                    pendingReads = selectionDelayReads
                } else {
                    range = selected
                    pendingSelection = nil
                }
            } else if !ignoreReplacement, let replacement = argument as? String {
                if name == kAXValueAttribute {
                    text = replacement
                    range = CFRange(location: text.utf16.count, length: 0)
                } else if name == kAXSelectedTextAttribute { applySelection(replacement) }
            }
            return .success
        }
        return access
    }

    private func applySelection(_ replacement: String) {
        guard !ignoreReplacement else { return }
        text = (text as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: replacement)
        range = CFRange(location: range.location + replacement.utf16.count, length: 0)
    }

    func replace(with replacement: String = "ивет", delimiter: String = " ") -> Bool {
        let original = context
        let injector = EventInjector(access: access, readCaret: { [unowned self] in
            reads += 1
            if let pending = pendingSelection {
                pendingReads -= 1
                if pendingReads == 0 {
                    range = pending
                    pendingSelection = nil
                }
            }
            if changeFocusOnRead == reads {
                var different = context
                different.element = AXUIElementCreateApplication(999_993)
                return different
            }
            return context
        }, secureInput: { [unowned self] in secure }, diagnostic: { [unowned self] in reasons.append($0) })
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
        let units = Array(delimiter.utf16)
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        return injector.replace(deleteCount: 4, with: replacement, trailingEvent: event, context: original)
    }
}
