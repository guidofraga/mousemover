import AppKit
import CoreGraphics
import ServiceManagement

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
    private var flickNowItem: NSMenuItem!
    private var statusItemInMenu: NSMenuItem!
    private var intervalMenu: NSMenu!
    private var durationMenu: NSMenu!
    private var launchAtLoginItem: NSMenuItem?
    private var needsPermission = false
    private var activity: NSObjectProtocol?
    private var isFlicking = false

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

    private var wasRunning: Bool {
        get { defaults.object(forKey: "wasRunning") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "wasRunning") }
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
        if wasRunning { start() }
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
        menu.autoenablesItems = false

        statusItemInMenu = NSMenuItem(title: "Off", action: nil, keyEquivalent: "")
        statusItemInMenu.isEnabled = false
        menu.addItem(statusItemInMenu)
        menu.addItem(.separator())

        toggleItem = NSMenuItem(title: "Turn On", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        flickNowItem = NSMenuItem(title: "Flick Now", action: #selector(flickNow), keyEquivalent: "")
        flickNowItem.target = self
        menu.addItem(flickNowItem)

        let intervalItem = NSMenuItem(title: "Flick Every", action: nil, keyEquivalent: "")
        intervalMenu = NSMenu(title: "Flick Every")
        intervalMenu.autoenablesItems = false
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        let durationItem = NSMenuItem(title: "Turn Off After", action: nil, keyEquivalent: "")
        durationMenu = NSMenu(title: "Turn Off After")
        durationMenu.autoenablesItems = false
        durationItem.submenu = durationMenu
        menu.addItem(durationItem)

        menu.addItem(.separator())
        let permissionItem = NSMenuItem(title: "Open Accessibility Settings...", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        if #available(macOS 13.0, *) {
            let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            loginItem.target = self
            menu.addItem(loginItem)
            launchAtLoginItem = loginItem
        }

        let quitItem = NSMenuItem(title: "Quit Mouse Mover", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func refreshMenu() {
        toggleItem.title = isRunning ? "Turn Off" : "Turn On"
        flickNowItem.isEnabled = isRunning
        rebuildIntervalMenu()
        rebuildDurationMenu()
        refreshLaunchAtLoginItem()
        updateStatusAppearance()
        updateMenuRefreshTimer()
    }

    private func updateStatusAppearance() {
        let status: String
        if isRunning {
            status = runningStatusText
        } else if needsPermission {
            status = "Off · Accessibility permission needed"
        } else {
            status = "Off"
        }
        statusItemInMenu.title = status
        if let button = statusItem.button {
            button.appearsDisabled = !isRunning
            button.toolTip = "Mouse Mover – \(status)"
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
        if needsPermission, AXIsProcessTrusted() {
            needsPermission = false
        }
        refreshLaunchAtLoginItem()
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
        let isCustom = !choices.contains(where: { $0.1 == interval })
        intervalMenu.addItem(.separator())
        let custom = NSMenuItem(
            title: isCustom ? "Custom (\(Self.formatInterval(interval)))..." : "Custom...",
            action: #selector(selectCustomInterval),
            keyEquivalent: ""
        )
        custom.target = self
        custom.state = isCustom ? .on : .off
        intervalMenu.addItem(custom)
    }

    private static func formatInterval(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds)
        if whole >= 60, whole % 60 == 0 {
            let minutes = whole / 60
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        return "\(whole) seconds"
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
        let isCustom = !choices.contains(where: { $0.1 == duration })
        durationMenu.addItem(.separator())
        let custom = NSMenuItem(
            title: isCustom ? "Custom (\(Self.formatInterval(duration ?? 0)))..." : "Custom...",
            action: #selector(selectCustomDuration),
            keyEquivalent: ""
        )
        custom.target = self
        custom.state = isCustom ? .on : .off
        durationMenu.addItem(custom)
    }

    private var runningStatusText: String {
        guard let runUntil else { return "On · runs until turned off" }
        let minutes = max(1, Int(ceil(runUntil.timeIntervalSinceNow / 60)))
        return "On · turns off in \(minutes) min"
    }

    @objc private func toggle() {
        if isRunning {
            wasRunning = false
            stop()
        } else {
            start()
        }
    }

    private func start() {
        if !AXIsProcessTrusted() {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            guard AXIsProcessTrustedWithOptions(options) else {
                needsPermission = true
                openAccessibilitySettings()
                refreshMenu()
                return
            }
        }

        needsPermission = false
        isRunning = true
        wasRunning = true
        lastFlick = nil
        beginActivity()
        restartFlickTimer()
        scheduleStop()
        refreshMenu()
    }

    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Keep the flick timer on schedule"
        )
    }

    private func endActivity() {
        guard let token = activity else { return }
        ProcessInfo.processInfo.endActivity(token)
        activity = nil
    }

    private func restartFlickTimer() {
        flickTimer?.invalidate()
        let timer = Timer(timeInterval: idlePollInterval, repeats: true) { [weak self] _ in
            self?.flickTick()
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        flickTimer = timer
    }

    private func flickTick() {
        guard isRunning else { return }
        if let runUntil, Date() >= runUntil {
            stop()
            return
        }
        maybeFlick()
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
        endActivity()
        refreshMenu()
    }

    private func maybeFlick() {
        guard isRunning else { return }
        guard AXIsProcessTrusted() else {
            permissionRevoked()
            return
        }
        if let lastFlick, Date().timeIntervalSince(lastFlick) < interval { return }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInputEventType)
        guard idle >= interval else { return }
        flickMouse()
    }

    private func permissionRevoked() {
        needsPermission = true
        stop()
        openAccessibilitySettings()
    }

    private func isAnyMouseButtonPressed() -> Bool {
        (0..<32).contains { raw in
            CGEventSource.buttonState(.hidSystemState, button: CGMouseButton(rawValue: UInt32(raw))!)
        }
    }

    private func flickMouse() {
        guard isRunning, !isFlicking, !isAnyMouseButtonPressed() else { return }
        guard let current = CGEvent(source: nil)?.location else { return }
        isFlicking = true
        lastFlick = Date()
        // Bounce away from the right screen edge so the +2px move never clamps off-screen.
        let delta: CGFloat
        if let bounds = Self.displayBounds(containing: current) {
            delta = (current.x + 2 <= bounds.maxX - 1) ? 2 : -2
        } else {
            delta = 2
        }
        let target = CGPoint(x: current.x + delta, y: current.y)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left)?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.isFlicking = false
            guard self.isRunning, !self.isAnyMouseButtonPressed() else { return }
            guard let now = CGEvent(source: nil)?.location,
                  abs(now.x - target.x) <= 0.5, abs(now.y - target.y) <= 0.5 else { return }
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: current, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }

    private static func displayBounds(containing point: CGPoint) -> CGRect? {
        var display = CGDirectDisplayID()
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else { return nil }
        return CGDisplayBounds(display)
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? TimeInterval else { return }
        interval = value
        if isRunning { restartFlickTimer() }
        refreshMenu()
    }

    @objc private func flickNow() {
        flickMouse()
    }

    @objc private func selectDuration(_ sender: NSMenuItem) {
        duration = (sender.representedObject as? NSNumber)?.doubleValue
        if isRunning { scheduleStop() } else { start() }
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
        if isRunning { scheduleStop() } else { start() }
        refreshMenu()
    }

    @objc private func selectCustomInterval() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Flick every"
        alert.informativeText = "Enter the number of seconds between flicks (5–86400)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = String(Int(interval))
        field.placeholderString = "Seconds"
        alert.accessoryView = field
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        field.selectText(nil)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let cleaned = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let seconds = Double(cleaned), seconds >= 5, seconds <= 86_400 else {
            NSSound.beep()
            return
        }
        interval = seconds
        if isRunning { restartFlickTimer() }
        refreshMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Could not update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshLaunchAtLoginItem()
    }

    private func refreshLaunchAtLoginItem() {
        guard #available(macOS 13.0, *), let item = launchAtLoginItem else { return }
        switch SMAppService.mainApp.status {
        case .enabled:
            item.title = "Launch at Login"
            item.state = .on
        case .requiresApproval:
            item.title = "Launch at Login (Needs Approval)"
            item.state = .off
        default:
            item.title = "Launch at Login"
            item.state = .off
        }
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
