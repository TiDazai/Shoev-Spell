import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = KeyboardMonitor()
    private var engine: SpellingEngine?
    private var menu: MenuBarController?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        Preferences.register()
        let engine = SpellingEngine()
        self.engine = engine
        monitor.delegate = engine
        menu = MenuBarController(monitor: monitor)
        if !monitor.start() { _ = monitor.requestPermissions() }
        menu?.refresh()
        permissionTimer = .scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if !self.monitor.isRunning { _ = self.monitor.start() }
            self.menu?.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        monitor.stop()
    }
}
