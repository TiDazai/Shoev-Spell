import AppKit
import ServiceManagement

final class MenuBarController: NSObject, NSMenuDelegate {
    private let monitor: KeyboardMonitor
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private lazy var enabled = item("Shoev Spell включён", #selector(toggleEnabled))
    private lazy var automatic = item("Исправлять автоматически", #selector(toggleAutomatic))
    private lazy var journal = item("Записывать исправления", #selector(toggleJournal))
    private lazy var login = item("Запускать при входе", #selector(toggleLogin))
    private lazy var permissions = item("Выдать системные разрешения…", #selector(requestPermissions))

    init(monitor: KeyboardMonitor) {
        self.monitor = monitor
        super.init()
        let image = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:))
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = image ?? NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Shoev Spell")
        statusItem.button?.imagePosition = .imageOnly
        menu.delegate = self
        menu.addItem(enabled)
        menu.addItem(automatic)
        menu.addItem(journal)
        menu.addItem(.separator())
        menu.addItem(login)
        menu.addItem(permissions)
        menu.addItem(.separator())
        menu.addItem(item("Завершить Shoev Spell", #selector(quit), key: "q"))
        statusItem.menu = menu
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    func refresh() {
        enabled.state = UserDefaults.standard.bool(forKey: PreferenceKey.enabled) ? .on : .off
        automatic.state = UserDefaults.standard.bool(forKey: PreferenceKey.automaticCorrection) ? .on : .off
        journal.state = UserDefaults.standard.bool(forKey: PreferenceKey.journalEnabled) ? .on : .off
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        permissions.isHidden = monitor.isRunning
        statusItem.button?.alphaValue = enabled.state == .on ? 1 : 0.45
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        return result
    }

    @objc private func toggleEnabled() { toggle(PreferenceKey.enabled) }
    @objc private func toggleAutomatic() { toggle(PreferenceKey.automaticCorrection) }
    @objc private func toggleJournal() { toggle(PreferenceKey.journalEnabled) }
    @objc private func requestPermissions() { _ = monitor.requestPermissions(); _ = monitor.start(); refresh() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { NSAlert(error: error).runModal() }
        refresh()
    }

    private func toggle(_ key: String) {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
        refresh()
    }
}
