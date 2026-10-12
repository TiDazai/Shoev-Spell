import XCTest
@testable import ShoevSpell

final class InputSafetyTests: XCTestCase {
    func testSpaceAndPunctuationCanBeInsertedWithTheCorrection() {
        for delimiter in [" ", ",", ".", "!", "…"] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
            let units = Array(delimiter.utf16)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            XCTAssertEqual(EventInjector.inlineDelimiter(event), delimiter)
        }
        let enter = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true)!
        enter.keyboardSetUnicodeString(stringLength: 1, unicodeString: [13])
        XCTAssertNil(EventInjector.inlineDelimiter(enter))
    }

    func testUnsupportedAlphabetsAreNotMisclassified() {
        XCTAssertNil(SpellLanguage.detect(in: "привіт"))
        XCTAssertNil(SpellLanguage.detect(in: "café"))
        XCTAssertNil(SpellLanguage.detect(in: "helloпривет"))
        XCTAssertEqual(SpellLanguage.detect(in: "Привет, ёж!"), .russian)
        XCTAssertEqual(SpellLanguage.detect(in: "Hello world!"), .english)
    }
    func testOnlyChangedSuffixIsReplaced() {
        let edit = TextReplacement(original: "я думаю что", replacement: "я думаю, что")
        XCTAssertEqual(edit.deleteCount, 4)
        XCTAssertEqual(edit.text, ", что")
        let terminal = TextReplacement(original: "готово", replacement: "готово.")
        XCTAssertEqual(terminal.deleteCount, 0)
        XCTAssertEqual(terminal.text, ".")
    }

    func testUnicodeSelectionUsesUTF16InsteadOfCharacterCount() {
        let prefix = "привет 👨‍👩‍👦"
        let range = TextReplacement.selection(prefix: prefix, deleteCount: 1)!
        XCTAssertEqual(range.location, "привет ".utf16.count)
        XCTAssertEqual(range.length, "👨‍👩‍👦".utf16.count)
        XCTAssertNil(TextReplacement.selection(prefix: "abc", deleteCount: 4))
        XCTAssertNil(TextReplacement.selection(prefix: "abc", deleteCount: -1))
        XCTAssertEqual(TextReplacement.selection(prefix: prefix, deleteCount: 0)?.location, prefix.utf16.count)
    }

    func testIdentifiersAndJoinedWordsAreNotNewWords() {
        for prefix in ["email@", "user_", "123", "don't", "из-", "/", "#"] {
            XCTAssertTrue(CaretContext(prefix: prefix, selectionLength: 0).startsInsideWord, prefix)
        }
    }

    func testPunctuationHandlesEmojiAndCompleteGreeting() {
        let engine = RussianPunctuationEngine()
        XCTAssertEqual(engine.punctuate("добрый день"), "добрый день")
        XCTAssertEqual(engine.punctuate("добрый человек"), "добрый человек")
        XCTAssertEqual(engine.punctuate("привет! Маша"), "привет! Маша")
        XCTAssertTrue(engine.punctuate("привет😀 Маша").contains("😀"))
    }
}
