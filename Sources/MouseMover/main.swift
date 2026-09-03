import AppKit
import CoreGraphics

@main
final class MouseMoverApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private var statusItem: NSStatusItem!
    private var flickTimer: Timer?
    private var stopTimer: Timer?
    private var menuRefreshTimer: Timer?
    private var isRunning = false
    private var runUntil: Date?
    private var lastFlick: Date?
    private let idlePollInterval: TimeInterval = 5
    private static let anyInputEventType = CGEventType(rawValue: UInt32.max)!

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
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }

    private static var retainedDelegate: MouseMoverApp?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenuBarItem()
        refreshMenu()
    }

    private func buildMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "Mouse Mover") {
                button.image = image
                button.image?.isTemplate = true
            } else {
                button.title = "MM"
            }
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
        rebuildIntervalMenu()
        rebuildDurationMenu()
        updateStatusAppearance()
        updateMenuRefreshTimer()
    }

    private func updateStatusAppearance() {
        let status = isRunning ? runningStatusText : "Off"
        statusItemInMenu.title = status
        if let button = statusItem.button {
            button.appearsDisabled = !isRunning
            button.toolTip = isRunning ? "Mouse Mover – \(status)" : "Mouse Mover – Off"
        }
    }

    private func updateMenuRefreshTimer() {
        menuRefreshTimer?.invalidate()
        menuRefreshTimer = nil
        guard isRunning else { return }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.updateStatusAppearance()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        menuRefreshTimer = timer
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateStatusAppearance()
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
        if !AXIsProcessTrusted() {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            guard AXIsProcessTrustedWithOptions(options) else {
                openAccessibilitySettings()
                return
            }
        }

        isRunning = true
        lastFlick = nil
        restartFlickTimer()
        scheduleStop()
        refreshMenu()
    }

    private func restartFlickTimer() {
        flickTimer?.invalidate()
        let timer = Timer(timeInterval: idlePollInterval, repeats: true) { [weak self] _ in
            self?.maybeFlick()
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        flickTimer = timer
    }

    private func scheduleStop() {
        stopTimer?.invalidate()
        stopTimer = nil
        if let duration {
            runUntil = Date().addingTimeInterval(duration)
            let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
                self?.stop()
            }
            RunLoop.main.add(timer, forMode: .common)
            stopTimer = timer
        } else {
            runUntil = nil
        }
    }

    private func stop() {
        isRunning = false
        flickTimer?.invalidate()
        stopTimer?.invalidate()
        menuRefreshTimer?.invalidate()
        flickTimer = nil
        stopTimer = nil
        menuRefreshTimer = nil
        runUntil = nil
        lastFlick = nil
        refreshMenu()
    }

    private func maybeFlick() {
        guard isRunning else { return }
        if let lastFlick, Date().timeIntervalSince(lastFlick) < interval { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInputEventType)
        guard idle >= interval else { return }
        flickMouse()
    }

    private func isAnyMouseButtonPressed() -> Bool {
        CGEventSource.buttonState(.hidSystemState, button: .left)
            || CGEventSource.buttonState(.hidSystemState, button: .right)
            || CGEventSource.buttonState(.hidSystemState, button: .center)
    }

    private func flickMouse() {
        guard isRunning, !isAnyMouseButtonPressed() else { return }
        guard let current = CGEvent(source: nil)?.location else { return }
        lastFlick = Date()
        // Bounce away from the right screen edge so the +2px move never clamps off-screen.
        let delta: CGFloat
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(current) }) ?? NSScreen.main {
            delta = (current.x + 2 <= NSMaxX(screen.frame) - 1) ? 2 : -2
        } else {
            delta = 2
        }
        let target = CGPoint(x: current.x + delta, y: current.y)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left)?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard self.isRunning, !self.isAnyMouseButtonPressed() else { return }
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
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Turn off after"
        alert.informativeText = "Enter the number of minutes Mouse Mover should stay on (1–1440)."
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
        alert.window.initialFirstResponder = field
        field.selectText(nil)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let cleaned = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let minutes = Double(cleaned), minutes >= 1, minutes <= 1440 else {
            NSSound.beep()
            return
        }
        duration = minutes * 60
        if isRunning { scheduleStop() }
        refreshMenu()
    }

    @objc private func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    @objc private func quit() {
        stop()
        NSApp.terminate(nil)
    }
}
