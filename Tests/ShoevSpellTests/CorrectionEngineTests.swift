import XCTest
@testable import ShoevSpell

private final class FakeLexicon: WordScoring {
    let values: [String: Int]
    init(_ values: [String: Int]) { self.values = values }
    func score(for word: String, language: SpellLanguage) -> Int? { values[word] }
}

final class CorrectionEngineTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "ShoevSpellTests-\(UUID().uuidString)"
        let result = UserDefaults(suiteName: suite)!
        result.set(3, forKey: PreferenceKey.minimumLength)
        result.set(250, forKey: PreferenceKey.minimumScore)
        return result
    }

    func testCorrectsSingleEdit() {
        let engine = CorrectionEngine(lexicon: FakeLexicon(["привет": 500]), defaults: defaults())
        XCTAssertEqual(engine.correction(for: "превет"), Correction(original: "превет", replacement: "привет"))
    }

    func testKeepsKnownWord() {
        let engine = CorrectionEngine(lexicon: FakeLexicon(["hello": 500]), defaults: defaults())
        XCTAssertNil(engine.correction(for: "hello"))
    }

    func testDoesNotGuessWhenCandidatesAreTooClose() {
        let engine = CorrectionEngine(lexicon: FakeLexicon(["cat": 400, "cut": 390]), defaults: defaults())
        XCTAssertNil(engine.correction(for: "cot"))
    }

    func testBundledLexiconContainsBothLanguages() {
        XCTAssertNotNil(Lexicon.shared.score(for: "zuckerberg", language: .english))
        XCTAssertNotNil(Lexicon.shared.score(for: "шоев", language: .russian))
    }

    func testBundledLexiconCorrectsRealTypos() {
        let engine = CorrectionEngine(lexicon: Lexicon.shared, defaults: defaults())
        XCTAssertEqual(engine.correction(for: "zuckreberg")?.replacement, "zuckerberg")
        XCTAssertEqual(engine.correction(for: "превет")?.replacement, "привет")
    }
}
