import Foundation

enum PreferenceKey {
    static let enabled = "enabled"
    static let automaticCorrection = "automaticCorrection"
    static let journalEnabled = "journalEnabled"
    static let minimumLength = "minimumLength"
    static let minimumScore = "minimumScore"
    static let excludedApplications = "excludedApplications"
}

enum Preferences {
    static func register() {
        UserDefaults.standard.register(defaults: [
            PreferenceKey.enabled: true,
            PreferenceKey.automaticCorrection: true,
            PreferenceKey.journalEnabled: true,
            PreferenceKey.minimumLength: 3,
            PreferenceKey.minimumScore: 250,
            PreferenceKey.excludedApplications: [
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "com.apple.dt.Xcode",
                "com.microsoft.VSCode"
            ]
        ])
    }
}
