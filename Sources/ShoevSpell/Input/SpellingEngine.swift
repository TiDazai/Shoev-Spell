import AppKit
import CoreGraphics
import Foundation
import OSLog

final class SpellingEngine: KeyboardMonitorDelegate {
    private let logger = Logger(subsystem: "com.shoev.spell", category: "input")
    private let corrector: CorrectionEngine
    private let punctuator: RussianPunctuationEngine
    private let injector: TextInjecting
    private let journal: JournalStore
    private var word = ""
    private var phrase = ""
    private var activePID: pid_t?
    private let readCaret: () -> CaretContext?
    private let defaults: UserDefaults
    private let frontmost: () -> NSRunningApplication?
    private var knownPrefix: String?
    private var editingWord = false

    init(
        corrector: CorrectionEngine = CorrectionEngine(),
        punctuator: RussianPunctuationEngine = RussianPunctuationEngine(),
        injector: TextInjecting = EventInjector(),
        journal: JournalStore = JournalStore(),
        defaults: UserDefaults = .standard,
        readCaret: @escaping () -> CaretContext? = { CaretContextReader().read() },
        frontmost: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }
    ) {
        self.corrector = corrector
        self.punctuator = punctuator
        self.injector = injector
        self.journal = journal
        self.defaults = defaults
        self.readCaret = readCaret
        self.frontmost = frontmost
    }

    func monitorDidReset(_ monitor: KeyboardMonitor) {
        if !phrase.isEmpty {
            logger.info("Input context reset externally; bufferedCharacters=\(self.phrase.count)")
        }
        reset()
    }

    func monitor(_ monitor: KeyboardMonitor, keyDown event: CGEvent, text: String, keyCode: CGKeyCode) -> Bool {
        let app = frontmost()
        if activePID != app?.processIdentifier {
            logger.info("Frontmost application changed; bufferedCharacters=\(self.phrase.count)")
            activePID = app?.processIdentifier
            reset()
        }
        guard defaults.bool(forKey: PreferenceKey.enabled), !isExcluded(app) else {
            reset(); return false
        }
        if event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty == false {
            logger.info("Input context reset by modifier; bufferedCharacters=\(self.phrase.count)")
            reset(); return false
        }
        if keyCode == 51 || keyCode == 117 {
            // Deletion can remove a selection, composed character or text outside
            // our buffer. Only start tracking again at a verified word boundary.
            reset()
            return false
        }
        if [123, 124, 125, 126, 115, 119, 116, 121].contains(keyCode) {
            logger.info("Input context reset by navigation; bufferedCharacters=\(self.phrase.count)")
            reset(); return false
        }
        guard !text.isEmpty else { reset(); return false }
        guard let caret = readCaret() else {
            reset()
            return false
        }
        do {
            if caret.selectionLength > 0 || (!phrase.isEmpty && !caret.prefix.hasSuffix(phrase)) {
                reset()
            }
            knownPrefix = caret.prefix
            if phrase.isEmpty { editingWord = caret.startsInsideWord || caret.selectionLength > 0 }
        }
        if text.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
            let shouldCapitalize = defaults.bool(forKey: PreferenceKey.automaticCapitalization)
                && !editingWord
                && knownPrefix.map { CapitalizationContext.shouldCapitalize(after: $0) } == true
            let capturedText = shouldCapitalize ? punctuator.capitalized(text) : text
            knownPrefix = knownPrefix.map { $0 + capturedText }
            if !editingWord {
                word += capturedText
                phrase += capturedText
            }
            if phrase.count > 500 || word.count > 32 {
                reset()
                editingWord = true
            }
            if capturedText != text {
                injector.replace(deleteCount: 0, with: capturedText, trailingEvent: nil)
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
        return defaults.stringArray(forKey: PreferenceKey.excludedApplications)?.contains(id) == true
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
           defaults.bool(forKey: PreferenceKey.automaticCorrection),
           let found = corrector.correction(for: word) {
            replacement.removeLast(word.count)
            replacement += found.replacement
            correction = found
        }

        if defaults.bool(forKey: PreferenceKey.automaticPunctuation) {
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
            // Re-read after candidate lookup: focus/selection may have changed.
            guard let caret = readCaret(), caret.selectionLength == 0,
                  frontmost()?.processIdentifier == application?.processIdentifier,
                  caret.prefix == knownPrefix,
                  caret.prefix.hasSuffix(originalPhrase),
                  !originalPhrase.isEmpty else { reset(); return false }
            let edit = TextReplacement(original: originalPhrase, replacement: replacement)
            injector.replace(deleteCount: edit.deleteCount, with: edit.text, trailingEvent: trailingEvent)
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

    private func reset() {
        knownPrefix = nil
        editingWord = false
        word.removeAll(keepingCapacity: true)
        phrase.removeAll(keepingCapacity: true)
    }
}
