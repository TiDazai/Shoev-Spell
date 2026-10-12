import AppKit
import XCTest
@testable import ShoevSpell

private final class CapturedInjection: TextInjecting {
    var calls: [(Int, String)] = []
    var succeeds = true
    func replace(deleteCount: Int, with replacement: String, trailingEvent: CGEvent?, context: CaretContext) -> Bool {
        calls.append((deleteCount, replacement))
        return succeeds
    }
}

final class SpellingEngineTests: XCTestCase {
    func testCorrectionResumesAfterDeletion() {
        let suite = "SpellingEngineTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PreferenceKey.enabled)
        defaults.set(true, forKey: PreferenceKey.automaticCorrection)
        defaults.set(3, forKey: PreferenceKey.minimumLength)
        defaults.set(250, forKey: PreferenceKey.minimumScore)
        var prefix = ""
        let injector = CapturedInjection()
        let engine = SpellingEngine(corrector: CorrectionEngine(defaults: defaults), injector: injector,
            defaults: defaults, readCaret: { CaretContext(prefix: prefix, selectionLength: 0) },
            frontmost: { nil })
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 35, keyDown: true)!
        event.flags = []
        let monitor = KeyboardMonitor()
        for _ in 0..<2 {
            for character in "превет" {
                XCTAssertFalse(engine.monitor(monitor, keyDown: event, text: String(character), keyCode: 35))
                prefix.append(character)
            }
            XCTAssertTrue(engine.monitor(monitor, keyDown: event, text: " ", keyCode: 49))
            XCTAssertFalse(engine.monitor(monitor, keyDown: event, text: "", keyCode: 51))
            prefix = ""
        }
        XCTAssertEqual(injector.calls.count, 2)
    }

    func testIdenticalTextInDifferentFieldsDoesNotMatch() {
        let first = CaretContext(prefix: "превет", selectionLength: 0,
            element: AXUIElementCreateApplication(11))
        let second = CaretContext(prefix: "превет", selectionLength: 0,
            element: AXUIElementCreateApplication(12))
        XCTAssertTrue(first.matches(first))
        XCTAssertFalse(first.matches(second))
    }

    func testFailedCapitalizationPreservesOriginalKey() {
        let suite = "SpellingEngineTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PreferenceKey.enabled)
        defaults.set(true, forKey: PreferenceKey.automaticCapitalization)
        let injector = CapturedInjection()
        injector.succeeds = false
        let engine = SpellingEngine(injector: injector, defaults: defaults,
            readCaret: { CaretContext(prefix: "", selectionLength: 0) }, frontmost: { nil })
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 35, keyDown: true)!
        event.flags = []
        XCTAssertFalse(engine.monitor(KeyboardMonitor(), keyDown: event, text: "п", keyCode: 35))
        XCTAssertEqual(injector.calls.first?.1, "П")
    }

    func testFailedWordCorrectionPreservesDelimiter() {
        let suite = "SpellingEngineTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PreferenceKey.enabled)
        defaults.set(true, forKey: PreferenceKey.automaticCorrection)
        defaults.set(3, forKey: PreferenceKey.minimumLength)
        defaults.set(250, forKey: PreferenceKey.minimumScore)
        var prefix = ""
        let injector = CapturedInjection()
        injector.succeeds = false
        let engine = SpellingEngine(corrector: CorrectionEngine(defaults: defaults), injector: injector, defaults: defaults,
            readCaret: { CaretContext(prefix: prefix, selectionLength: 0) }, frontmost: { nil })
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        event.flags = []
        let monitor = KeyboardMonitor()
        for character in "превет" {
            XCTAssertFalse(engine.monitor(monitor, keyDown: event, text: String(character), keyCode: 0))
            prefix.append(character)
        }
        XCTAssertFalse(engine.monitor(monitor, keyDown: event, text: " ", keyCode: 49))
        XCTAssertEqual(injector.calls.first?.1, "ивет")
    }

    func testUnavailableFieldNeverGetsCapitalizedOrPunctuated() {
        exercise(nil, input: "превет ", expectedCalls: 0)
    }

    func testSelectionIsNeverAutomaticallyCapitalized() {
        exercise(CaretContext(prefix: "", selectionLength: 6), input: "п", expectedCalls: 0)
    }

    func testEditingAtStartOfExistingWordPreservesCase() {
        exercise(CaretContext(prefix: "", selectionLength: 0, nextCharacter: "р"), input: "п", expectedCalls: 0)
    }

    private func exercise(_ caret: CaretContext?, input: String, expectedCalls: Int) {
        let suite = "SpellingEngineTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PreferenceKey.enabled)
        defaults.set(true, forKey: PreferenceKey.automaticCapitalization)
        defaults.set(true, forKey: PreferenceKey.automaticPunctuation)
        let injector = CapturedInjection()
        let engine = SpellingEngine(injector: injector, defaults: defaults, readCaret: { caret }, frontmost: { nil })
        let monitor = KeyboardMonitor()
        for c in input {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
            event.flags = []
            XCTAssertFalse(engine.monitor(monitor, keyDown: event, text: String(c), keyCode: 0))
        }
        XCTAssertEqual(injector.calls.count, expectedCalls)
    }
}
