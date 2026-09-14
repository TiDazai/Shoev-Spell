import AppKit
import CoreGraphics
import Foundation

final class SpellingEngine: KeyboardMonitorDelegate {
    private let corrector: CorrectionEngine
    private let injector: EventInjector
    private let journal: JournalStore
    private var word = ""
    private var activePID: pid_t?

    init(corrector: CorrectionEngine = CorrectionEngine(), injector: EventInjector = EventInjector(), journal: JournalStore = JournalStore()) {
        self.corrector = corrector
        self.injector = injector
        self.journal = journal
    }

    func monitorDidReset(_ monitor: KeyboardMonitor) { reset() }

    func monitor(_ monitor: KeyboardMonitor, keyDown event: CGEvent, text: String, keyCode: CGKeyCode) -> Bool {
        let app = NSWorkspace.shared.frontmostApplication
        if activePID != app?.processIdentifier {
            activePID = app?.processIdentifier
            reset()
        }
        guard UserDefaults.standard.bool(forKey: PreferenceKey.enabled), !isExcluded(app) else {
            reset(); return false
        }
        if event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty == false {
            reset(); return false
        }
        if keyCode == 51 {
            if !word.isEmpty { word.removeLast() }
            return false
        }
        if [123, 124, 125, 126, 115, 119, 116, 121].contains(keyCode) {
            reset(); return false
        }
        guard !text.isEmpty else { return false }
        if text.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) {
            word += text
            return false
        }
        guard !word.isEmpty else { return false }
        defer { reset() }
        guard UserDefaults.standard.bool(forKey: PreferenceKey.automaticCorrection),
              let correction = corrector.correction(for: word) else { return false }
        injector.replace(deleteCount: word.count, with: correction.replacement, trailingEvent: event)
        journal.record(correction, application: app)
        return true
    }

    private func isExcluded(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return UserDefaults.standard.stringArray(forKey: PreferenceKey.excludedApplications)?.contains(id) == true
    }

    private func reset() { word.removeAll(keepingCapacity: true) }
}
