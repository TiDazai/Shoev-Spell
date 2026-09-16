import AppKit
import XCTest
@testable import ShoevSpell

private final class CapturedInjection: TextInjecting {
    var calls: [(Int, String)] = []
    func replace(deleteCount: Int, with replacement: String, trailingEvent: CGEvent?) {
        calls.append((deleteCount, replacement))
    }
}

final class SpellingEngineTests: XCTestCase {
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
