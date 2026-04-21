import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = UpdateManager()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var prefsWindow: NSWindow?
    private var observer: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()

        // Refresh on launch.
        Task { await manager.refreshIfStale() }

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

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusButton()
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let name = manager.isWorking ? "arrow.triangle.2.circlepath" : "shippingbox"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Current")
        button.image?.isTemplate = true
        button.title = manager.visibleCount > 0 ? " \(manager.visibleCount)" : ""
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
        popover.contentSize = NSSize(width: 340, height: 480)
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

extension Notification.Name {
    static let currentMenuBarShouldUpdate = Notification.Name("com.elias.current.menuBarShouldUpdate")
    static let currentOpenPreferences = Notification.Name("com.elias.current.openPreferences")
}
