import XCTest
@testable import ShoevSpell

final class InputSafetyTests: XCTestCase {
    func testOnlyChangedSuffixIsReplaced() {
        let edit = TextReplacement(original: "я думаю что", replacement: "я думаю, что")
        XCTAssertEqual(edit.deleteCount, 4)
        XCTAssertEqual(edit.text, ", что")
        let terminal = TextReplacement(original: "готово", replacement: "готово.")
        XCTAssertEqual(terminal.deleteCount, 0)
        XCTAssertEqual(terminal.text, ".")
    }

    func testLongUnicodeReplacementIsLossless() {
        let text = String(repeating: "я", count: 19) + "😀" + String(repeating: "привет 👨‍👩‍👦 ", count: 50)
        let chunks = TextReplacement.unicodeChunks(text)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 20 })
        XCTAssertEqual(chunks.map { String(decoding: $0, as: UTF16.self) }.joined(), text)
        XCTAssertTrue(TextReplacement.unicodeChunks("").isEmpty)
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
