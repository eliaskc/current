import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let manager = UpdateManager()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var prefsWindow: NSWindow?
    private var observer: NSObjectProtocol?
    private var popoverCloseObserver: NSObjectProtocol?
    private var backgroundTimer: Timer?
    private var statusSpinner: StatusSpinnerView?
    private var statusIconView: NSImageView?
    private var statusBadgeView: StatusBadgeView?

    /// How often the background ticker checks staleness. The actual refresh
    /// cadence is controlled by `UpdateManager.refreshIntervalHours`; this just
    /// decides how fine-grained the wake-up is.
    private let backgroundTickInterval: TimeInterval = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()

        // Refresh on launch.
        Task { await manager.refreshIfStale() }

        // Periodic background refresh. Without this, the app only re-checks
        // when the popover is opened, so a left-alone menu bar would happily
        // sit on "23 hours ago" forever. No entitlement required — we're
        // unsandboxed and LSUIElement means the process stays alive.
        scheduleBackgroundRefresh()

        // Re-check after the machine wakes from sleep. Timers pause during
        // sleep, so without this the first post-wake tick could be up to
        // `backgroundTickInterval` late.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        // Re-render the menu bar label when counts or status change.
        observer = NotificationCenter.default.addObserver(
            forName: .currentMenuBarShouldUpdate, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateStatusButton() }
        }

        // Opening preferences from inside the popover UI.
        NotificationCenter.default.addObserver(
            forName: .currentOpenPreferences, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.popover.performClose(nil)
                self?.openPreferences()
            }
        }
    }

    private func scheduleBackgroundRefresh() {
        let timer = Timer(timeInterval: backgroundTickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.manager.refreshIfStale() }
        }
        // `.common` so menu tracking / popover interaction doesn't pause it.
        RunLoop.main.add(timer, forMode: .common)
        backgroundTimer = timer
    }

    @objc private func systemDidWake(_ note: Notification) {
        Task { @MainActor in await manager.refreshIfStale() }
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in self.manager.clearCompleted() }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        installStatusSpinner(in: button)
        updateStatusButton()
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }

        let count = manager.pendingCount
        statusBadgeView?.count = count

        if manager.isWorking {
            statusIconView?.isHidden = true
            statusSpinner?.isHidden = false
            statusSpinner?.startAnimation(nil)
        } else {
            statusSpinner?.stopAnimation(nil)
            statusSpinner?.isHidden = true
            statusIconView?.isHidden = false
        }
        button.image = nil
        button.title = ""
        button.alphaValue = 1.0
    }

    private func installStatusSpinner(in button: NSStatusBarButton) {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "Current")
        icon.image?.isTemplate = true
        icon.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let spinner = StatusSpinnerView()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true

        let badge = StatusBadgeView()
        badge.translatesAutoresizingMaskIntoConstraints = false

        button.addSubview(icon)
        button.addSubview(spinner)
        button.addSubview(badge)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            spinner.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),

            badge.leadingAnchor.constraint(equalTo: icon.centerXAnchor, constant: 5),
            badge.topAnchor.constraint(equalTo: icon.topAnchor, constant: -2),
            badge.widthAnchor.constraint(equalToConstant: 6),
            badge.heightAnchor.constraint(equalToConstant: 6)
        ])

        // Match a normal square menu-bar extra. Update availability is shown
        // as a tiny monochrome status dot instead of a numeric badge, which is
        // closer to Apple's menu-bar-extra guidance.
        statusItem.length = NSStatusItem.squareLength
        statusIconView = icon
        statusSpinner = spinner
        statusBadgeView = badge
    }

    @objc private func handleStatusClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popoverCloseObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification, object: popover, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.manager.clearCompleted() }
        }
        popover.contentSize = NSSize(width: 400, height: 420)
        let root = RootView()
            .environmentObject(manager)
            .onAppear { [weak self] in
                Task { await self?.manager.refreshIfStale() }
            }
        popover.contentViewController = NSHostingController(rootView: root)
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Right-click menu

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(item("Refresh Packages", #selector(checkNow), key: "r", symbol: "arrow.clockwise"))
        menu.addItem(item("Preferences…", #selector(openPreferences), key: ",", symbol: "gearshape"))
        menu.addItem(.separator())
        menu.addItem(statsItem())
        menu.addItem(.separator())
        menu.addItem(versionItem())
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(quit), key: "q"))

        // Attach menu, simulate click, detach so left-click still opens popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, _ selector: Selector, key: String, symbol: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        i.target = self
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return i
    }

    private func versionItem() -> NSMenuItem {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let i = NSMenuItem(title: "Version \(version)", action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func statsItem() -> NSMenuItem {
        let s = manager.stats
        let title: String = s.total == 0
            ? "No updates yet"
            : "\(s.lastWeek) updates this week · \(s.total) all time"
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        i.isEnabled = false
        return i
    }

    @objc private func checkNow() { Task { await manager.refresh() } }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openPreferences() {
        if let existing = prefsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = PreferencesView().environmentObject(manager)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Current Preferences"
        window.contentViewController = NSHostingController(rootView: view)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        prefsWindow = window
    }
}

private final class StatusBadgeView: NSView {
    var count: Int = 0 {
        didSet {
            isHidden = count <= 0
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isHidden = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard count > 0 else { return }

        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(ovalIn: rect)
        NSColor.labelColor.withAlphaComponent(0.85).setFill()
        path.fill()
    }
}

private final class StatusSpinnerView: NSView {
    private var timer: Timer?
    private var frameIndex = 0

    var isAnimating: Bool { timer != nil }

    func startAnimation(_ sender: Any?) {
        guard timer == nil else { return }
        isHidden = false
        let timer = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.frameIndex = (self.frameIndex + 1) % 12
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopAnimation(_ sender: Any?) {
        timer?.invalidate()
        timer = nil
        frameIndex = 0
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let tickCount = 12
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outerRadius = min(bounds.width, bounds.height) * 0.45
        let innerRadius = outerRadius * 0.48
        let lineWidth = max(1.5, outerRadius * 0.17)

        context.setLineCap(.round)
        context.setLineWidth(lineWidth)

        let baseColor = NSColor.labelColor.withSystemEffect(.pressed)
        for i in 0..<tickCount {
            let age = (i - frameIndex + tickCount) % tickCount
            let alpha = 0.18 + (1.0 - CGFloat(age) / CGFloat(tickCount - 1)) * 0.72
            context.setStrokeColor(baseColor.withAlphaComponent(alpha).cgColor)

            let angle = (CGFloat(i) / CGFloat(tickCount)) * .pi * 2 - .pi / 2
            let start = CGPoint(
                x: center.x + cos(angle) * innerRadius,
                y: center.y + sin(angle) * innerRadius
            )
            let end = CGPoint(
                x: center.x + cos(angle) * outerRadius,
                y: center.y + sin(angle) * outerRadius
            )
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }
    }
}

extension Notification.Name {
    static let currentMenuBarShouldUpdate = Notification.Name("com.elias.current.menuBarShouldUpdate")
    static let currentOpenPreferences = Notification.Name("com.elias.current.openPreferences")
}
