import AppKit
import CoreGraphics
import Foundation
import OSLog

final class SpellingEngine: KeyboardMonitorDelegate {
    private let logger = Logger(subsystem: "com.shoev.spell", category: "input")
    private let corrector: CorrectionEngine
    private let punctuator: RussianPunctuationEngine
    private let injector: EventInjector
    private let journal: JournalStore
    private var word = ""
    private var phrase = ""
    private var activePID: pid_t?
    private let caretReader = CaretContextReader()
    private var knownPrefix: String?
    private var editingWord = false

    init(
        corrector: CorrectionEngine = CorrectionEngine(),
        punctuator: RussianPunctuationEngine = RussianPunctuationEngine(),
        injector: EventInjector = EventInjector(),
        journal: JournalStore = JournalStore()
    ) {
        self.corrector = corrector
        self.punctuator = punctuator
        self.injector = injector
        self.journal = journal
    }

    func monitorDidReset(_ monitor: KeyboardMonitor) {
        if !phrase.isEmpty {
            logger.info("Input context reset externally; bufferedCharacters=\(self.phrase.count)")
        }
        reset()
    }

    func monitor(_ monitor: KeyboardMonitor, keyDown event: CGEvent, text: String, keyCode: CGKeyCode) -> Bool {
        let app = NSWorkspace.shared.frontmostApplication
        if activePID != app?.processIdentifier {
            logger.info("Frontmost application changed; bufferedCharacters=\(self.phrase.count)")
            activePID = app?.processIdentifier
            reset()
        }
        guard UserDefaults.standard.bool(forKey: PreferenceKey.enabled), !isExcluded(app) else {
            reset(); return false
        }
        if event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty == false {
            logger.info("Input context reset by modifier; bufferedCharacters=\(self.phrase.count)")
            reset(); return false
        }
        if keyCode == 51 {
            knownPrefix = nil
            if !phrase.isEmpty { phrase.removeLast() }
            rebuildCurrentWord()
            return false
        }
        if [123, 124, 125, 126, 115, 119, 116, 121].contains(keyCode) {
            logger.info("Input context reset by navigation; bufferedCharacters=\(self.phrase.count)")
            reset(); return false
        }
        guard !text.isEmpty else { return false }
        let caret = caretReader.read()
        if let caret {
            if caret.selectionLength > 0 || (!phrase.isEmpty && !caret.prefix.hasSuffix(phrase)) {
                reset()
            }
            knownPrefix = caret.prefix
            if phrase.isEmpty { editingWord = caret.startsInsideWord || caret.selectionLength > 0 }
        }
        if text.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
            let shouldCapitalize = UserDefaults.standard.bool(forKey: PreferenceKey.automaticCapitalization)
                && knownPrefix.map { CapitalizationContext.shouldCapitalize(after: $0) } == true
            let capturedText = shouldCapitalize ? punctuator.capitalized(text) : text
            knownPrefix = knownPrefix.map { $0 + capturedText }
            if !editingWord {
                word += capturedText
                phrase += capturedText
            }
            if phrase.count > 500 {
                phrase = word
            }
            if capturedText != text {
                injector.replace(deleteCount: 0, with: capturedText)
                return true
            }
            return false
        }

        if text == " " {
            let result = finishSegment(trailingEvent: event, delimiter: text, endsSentence: false, application: app)
            knownPrefix = knownPrefix.map { $0 + text }
            editingWord = false
            return result
        }
        if text == "\r" || text == "\n" {
            let result = finishSegment(trailingEvent: event, delimiter: text, endsSentence: true, application: app)
            knownPrefix = "\n"
            editingWord = false
            return result
        }
        if text.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: ",.;:!?…").contains($0) }) {
            let endsSentence = text.unicodeScalars.contains { CharacterSet(charactersIn: ".!?…").contains($0) }
            let prefix = knownPrefix
            let result = finishSegment(trailingEvent: event, delimiter: text, endsSentence: endsSentence, application: app)
            knownPrefix = prefix.map { $0 + text }
            editingWord = false
            return result
        }

        let prefix = knownPrefix
        reset()
        knownPrefix = prefix.map { $0 + text }
        return false
    }

    private func isExcluded(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return UserDefaults.standard.stringArray(forKey: PreferenceKey.excludedApplications)?.contains(id) == true
    }

    private func finishSegment(
        trailingEvent: CGEvent,
        delimiter: String,
        endsSentence: Bool,
        application: NSRunningApplication?
    ) -> Bool {
        let originalPhrase = phrase
        var replacement = phrase
        var correction: Correction?

        if !word.isEmpty,
           UserDefaults.standard.bool(forKey: PreferenceKey.automaticCorrection),
           let found = corrector.correction(for: word) {
            replacement.removeLast(word.count)
            replacement += found.replacement
            correction = found
        }

        if UserDefaults.standard.bool(forKey: PreferenceKey.automaticPunctuation) {
            let beforePunctuation = replacement
            replacement = punctuator.punctuate(replacement)
            logger.info("Punctuation evaluated; bufferedCharacters=\(originalPhrase.count), wordCharacters=\(self.word.count), changed=\(beforePunctuation != replacement)")
            if delimiter == "\r" || delimiter == "\n" {
                replacement = replacement.trimmingCharacters(in: .whitespaces)
                if let last = replacement.last,
                   CharacterSet(charactersIn: ".!?…:;").contains(last.unicodeScalars.first!) == false {
                    replacement.append(punctuator.terminalMark(for: replacement))
                }
            }
        }

        if replacement != originalPhrase {
            injector.replace(deleteCount: originalPhrase.count, with: replacement, trailingEvent: trailingEvent)
            if let correction { journal.record(correction, application: application) }
            if endsSentence {
                reset()
            } else {
                phrase = replacement + delimiter
                word.removeAll(keepingCapacity: true)
            }
            return true
        }

        if let correction { journal.record(correction, application: application) }
        if endsSentence {
            reset()
        } else {
            phrase += delimiter
            word.removeAll(keepingCapacity: true)
        }
        return false
    }

    private func rebuildCurrentWord() {
        word = String(phrase.reversed().prefix { character in
            character.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
        }.reversed())
    }

    private func reset() {
        knownPrefix = nil
        editingWord = false
        word.removeAll(keepingCapacity: true)
        phrase.removeAll(keepingCapacity: true)
    }
}
