import AppKit
import Foundation

final class JournalStore {
    private let queue = DispatchQueue(label: "com.shoev.spell.journal")
    private let url: URL?

    init() {
        let manager = FileManager.default
        let base = try? manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Shoev Spell", isDirectory: true)
        if let base { try? manager.createDirectory(at: base, withIntermediateDirectories: true) }
        url = base?.appendingPathComponent("corrections.jsonl")
    }

    func record(_ correction: Correction, application: NSRunningApplication?) {
        guard UserDefaults.standard.bool(forKey: PreferenceKey.journalEnabled), let url else { return }
        let record: [String: Any] = [
            "date": ISO8601DateFormatter().string(from: Date()),
            "application": application?.bundleIdentifier ?? "",
            "original": correction.original,
            "replacement": correction.replacement
        ]
        queue.async {
            guard let data = try? JSONSerialization.data(withJSONObject: record),
                  var line = String(data: data, encoding: .utf8)?.data(using: .utf8) else { return }
            line.append(0x0A)
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }
}
