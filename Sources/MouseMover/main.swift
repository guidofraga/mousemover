import AppKit
import CoreGraphics

@main
final class MouseMoverApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var flickTimer: Timer?
    private var stopTimer: Timer?
    private var isRunning = false
    private var runUntil: Date?

    private var toggleItem: NSMenuItem!
    private var statusItemInMenu: NSMenuItem!
    private var intervalMenu: NSMenu!
    private var durationMenu: NSMenu!

    private var interval: TimeInterval {
        get { defaults.object(forKey: "interval") as? TimeInterval ?? 5 * 60 }
        set { defaults.set(newValue, forKey: "interval") }
    }

    private var duration: TimeInterval? {
        get {
            let value = defaults.double(forKey: "duration")
            return value > 0 ? value : nil
        }
        set { defaults.set(newValue ?? 0, forKey: "duration") }
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = MouseMoverApp()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenuBarItem()
        refreshMenu()
    }

    private func buildMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "Mouse Mover")
            button.image?.isTemplate = true
            button.toolTip = "Mouse Mover"
        }

        let menu = NSMenu()
        menu.delegate = self

        statusItemInMenu = NSMenuItem(title: "Off", action: nil, keyEquivalent: "")
        statusItemInMenu.isEnabled = false
        menu.addItem(statusItemInMenu)
        menu.addItem(.separator())

        toggleItem = NSMenuItem(title: "Turn On", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let intervalItem = NSMenuItem(title: "Flick Every", action: nil, keyEquivalent: "")
        intervalMenu = NSMenu(title: "Flick Every")
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        let durationItem = NSMenuItem(title: "Turn Off After", action: nil, keyEquivalent: "")
        durationMenu = NSMenu(title: "Turn Off After")
        durationItem.submenu = durationMenu
        menu.addItem(durationItem)

        menu.addItem(.separator())
        let permissionItem = NSMenuItem(title: "Open Accessibility Settings...", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        let quitItem = NSMenuItem(title: "Quit Mouse Mover", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func refreshMenu() {
        toggleItem.title = isRunning ? "Turn Off" : "Turn On"
        statusItemInMenu.title = isRunning ? runningStatusText : "Off"
        rebuildIntervalMenu()
        rebuildDurationMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        statusItemInMenu.title = isRunning ? runningStatusText : "Off"
    }

    private func rebuildIntervalMenu() {
        intervalMenu.removeAllItems()
        let choices: [(String, TimeInterval)] = [
            ("1 minute", 60), ("5 minutes", 300), ("10 minutes", 600),
            ("15 minutes", 900), ("30 minutes", 1800), ("1 hour", 3600)
        ]
        for (title, value) in choices {
            let item = NSMenuItem(title: title, action: #selector(selectInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = interval == value ? .on : .off
            intervalMenu.addItem(item)
        }
    }

    private func rebuildDurationMenu() {
        durationMenu.removeAllItems()
        let choices: [(String, TimeInterval?)] = [
            ("Never", nil), ("15 minutes", 900), ("30 minutes", 1800),
            ("1 hour", 3600), ("2 hours", 7200)
        ]
        for (title, value) in choices {
            let item = NSMenuItem(title: title, action: #selector(selectDuration(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value.map { NSNumber(value: $0) }
            item.state = duration == value ? .on : .off
            durationMenu.addItem(item)
        }
        durationMenu.addItem(.separator())
        let custom = NSMenuItem(title: "Custom...", action: #selector(selectCustomDuration), keyEquivalent: "")
        custom.target = self
        durationMenu.addItem(custom)
    }

    private var runningStatusText: String {
        guard let runUntil else { return "On · runs until turned off" }
        let minutes = max(1, Int(ceil(runUntil.timeIntervalSinceNow / 60)))
        return "On · turns off in \(minutes) min"
    }

    @objc private func toggle() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    private func start() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        guard AXIsProcessTrustedWithOptions(options) else {
            openAccessibilitySettings()
            return
        }

        isRunning = true
        restartFlickTimer()
        scheduleStop()
        refreshMenu()
    }

    private func restartFlickTimer() {
        flickTimer?.invalidate()
        flickTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.flickMouse()
        }
        flickTimer?.tolerance = min(10, interval * 0.05)
    }

    private func scheduleStop() {
        stopTimer?.invalidate()
        stopTimer = nil
        if let duration {
            runUntil = Date().addingTimeInterval(duration)
            stopTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.stop()
            }
        } else {
            runUntil = nil
        }
    }

    private func stop() {
        isRunning = false
        flickTimer?.invalidate()
        stopTimer?.invalidate()
        flickTimer = nil
        stopTimer = nil
        runUntil = nil
        refreshMenu()
    }

    private func flickMouse() {
        guard isRunning, !CGEventSource.buttonState(.hidSystemState, button: .left),
              !CGEventSource.buttonState(.hidSystemState, button: .right) else { return }
        guard let current = CGEvent(source: nil)?.location else { return }
        let target = CGPoint(x: current.x + 2, y: current.y)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left)?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard self.isRunning else { return }
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: current, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? TimeInterval else { return }
        interval = value
        if isRunning { restartFlickTimer() }
        refreshMenu()
    }

    @objc private func selectDuration(_ sender: NSMenuItem) {
        duration = (sender.representedObject as? NSNumber)?.doubleValue
        if isRunning { scheduleStop() }
        refreshMenu()
    }

    @objc private func selectCustomDuration() {
        let alert = NSAlert()
        alert.messageText = "Turn off after"
        alert.informativeText = "Enter the number of minutes Mouse Mover should stay on."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        if let duration {
            field.stringValue = String(Int(duration / 60))
        } else {
            field.stringValue = "60"
        }
        field.placeholderString = "Minutes"
        alert.accessoryView = field
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
              let minutes = Double(field.stringValue), minutes > 0 else { return }
        duration = minutes * 60
        if isRunning { scheduleStop() }
        refreshMenu()
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quit() {
        stop()
        NSApp.terminate(nil)
    }
}
