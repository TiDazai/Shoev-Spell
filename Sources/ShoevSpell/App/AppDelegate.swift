import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = KeyboardMonitor()
    private var engine: SpellingEngine?
    private var menu: MenuBarController?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.register()
        let engine = SpellingEngine()
        self.engine = engine
        monitor.delegate = engine
        menu = MenuBarController(monitor: monitor)
        guard !monitor.start() else { return }
        _ = monitor.requestPermissions()
        permissionTimer = .scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard self.monitor.start() else { return }
            self.menu?.refresh()
            timer.invalidate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        monitor.stop()
    }
}
