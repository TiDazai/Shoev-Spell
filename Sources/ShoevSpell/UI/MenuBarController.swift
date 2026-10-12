import AppKit
import ServiceManagement

final class MenuBarController: NSObject, NSMenuDelegate {
    private let monitor: KeyboardMonitor
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private lazy var enabled = item("Shoev Spell включён", #selector(toggleEnabled))
    private lazy var automatic = item("Исправлять автоматически", #selector(toggleAutomatic))
    private lazy var punctuation = item("Расставлять знаки препинания", #selector(togglePunctuation))
    private lazy var capitalization = item("Начинать предложения с заглавной", #selector(toggleCapitalization))
    private lazy var journal = item("Записывать исправления", #selector(toggleJournal))
    private lazy var login = item("Запускать при входе", #selector(toggleLogin))
    private lazy var permissions = item("Выдать системные разрешения…", #selector(requestPermissions))
    private lazy var exclusion = item("Не исправлять в текущем приложении", #selector(excludeCurrentApplication))

    init(monitor: KeyboardMonitor) {
        self.monitor = monitor
        super.init()
        let image = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:))
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        statusItem.button?.image = image ?? NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Shoev Spell")
        statusItem.button?.imagePosition = .imageOnly
        menu.delegate = self
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(enabled)
        menu.addItem(automatic)
        menu.addItem(punctuation)
        menu.addItem(capitalization)
        menu.addItem(journal)
        menu.addItem(.separator())
        menu.addItem(login)
        menu.addItem(permissions)
        menu.addItem(exclusion)
        menu.addItem(item("Открыть журнал исправлений…", #selector(openJournal)))
        menu.addItem(.separator())
        menu.addItem(item("О Shoev Spell…", #selector(showAbout)))
        menu.addItem(item("Завершить Shoev Spell", #selector(quit), key: "q"))
        statusItem.menu = menu
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    func refresh() {
        enabled.state = UserDefaults.standard.bool(forKey: PreferenceKey.enabled) ? .on : .off
        automatic.state = UserDefaults.standard.bool(forKey: PreferenceKey.automaticCorrection) ? .on : .off
        punctuation.state = UserDefaults.standard.bool(forKey: PreferenceKey.automaticPunctuation) ? .on : .off
        capitalization.state = UserDefaults.standard.bool(forKey: PreferenceKey.automaticCapitalization) ? .on : .off
        journal.state = UserDefaults.standard.bool(forKey: PreferenceKey.journalEnabled) ? .on : .off
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        permissions.isHidden = monitor.isRunning
        statusItem.button?.alphaValue = enabled.state == .on ? 1 : 0.45
        status.title = enabled.state == .off ? "Исправление приостановлено"
            : monitor.isRunning ? "Готов к исправлению" : "Нужны системные разрешения"
        statusItem.button?.toolTip = "Shoev Spell — \(status.title.lowercased())"
        let current = NSWorkspace.shared.frontmostApplication
        let identifier = current?.bundleIdentifier
        exclusion.title = "Не исправлять в \(current?.localizedName ?? "текущем приложении")"
        exclusion.isEnabled = identifier != nil && identifier != Bundle.main.bundleIdentifier
        exclusion.state = identifier.map {
            (UserDefaults.standard.stringArray(forKey: PreferenceKey.excludedApplications) ?? []).contains($0)
        } == true ? .on : .off
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        return result
    }

    @objc private func toggleEnabled() { toggle(PreferenceKey.enabled) }
    @objc private func toggleAutomatic() { toggle(PreferenceKey.automaticCorrection) }
    @objc private func togglePunctuation() { toggle(PreferenceKey.automaticPunctuation) }
    @objc private func toggleCapitalization() { toggle(PreferenceKey.automaticCapitalization) }
    @objc private func toggleJournal() { toggle(PreferenceKey.journalEnabled) }
    @objc private func requestPermissions() {
        let granted = monitor.requestPermissions()
        if granted {
            _ = monitor.start()
            refresh()
        } else {
            monitor.openMissingPermissionSettings()
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openJournal() {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true) else { return }
        let directory = base.appendingPathComponent("Shoev Spell", isDirectory: true)
        let file = directory.appendingPathComponent("corrections.jsonl")
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else { NSWorkspace.shared.open(directory) }
    }

    @objc private func excludeCurrentApplication() {
        guard let app = NSWorkspace.shared.frontmostApplication, let identifier = app.bundleIdentifier,
              identifier != Bundle.main.bundleIdentifier else { return }
        var exclusions = UserDefaults.standard.stringArray(forKey: PreferenceKey.excludedApplications) ?? []
        if exclusions.contains(identifier) { exclusions.removeAll { $0 == identifier } }
        else { exclusions.append(identifier) }
        UserDefaults.standard.set(exclusions, forKey: PreferenceKey.excludedApplications)
        refresh()
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Shoev Spell", .applicationVersion: version,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"):
                Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "SHOEV SYSTEMS"
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

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
