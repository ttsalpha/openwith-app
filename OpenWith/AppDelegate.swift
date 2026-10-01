import AppKit
import Observation
import SwiftUI

/// Owns the status item and routes every URL macOS hands the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private lazy var picker = PickerController(model: model)
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        refreshStatusIcon()
        observeSetupState()

        // Nothing reaches the app until it holds the handler, so the first run
        // opens Settings rather than parking an inert icon.
        if AppModel.consumeFirstLaunch(), !model.isDefaultBrowser {
            SettingsWindow.shared.show(model: model)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Read before anything can await: ⌥ is the escape hatch out of a saved
        // rule, and it is released the moment the browser comes up.
        let overridden = NSEvent.modifierFlags.contains(.option)
        let point = NSEvent.mouseLocation

        let web = urls.filter { $0.scheme == "http" || $0.scheme == "https" }
        guard !web.isEmpty else { return }

        guard !overridden else {
            picker.show(urls: web, at: point)
            return
        }

        // Per URL: a batch spanning domains has no single answer, and the
        // first URL's rule is not an answer for the rest.
        var unrouted: [URL] = []
        for url in web {
            if let browser = model.route(url) {
                Launcher.open([url], in: browser, isPrivate: false)
            } else {
                unrouted.append(url)
            }
        }
        guard !unrouted.isEmpty else { return }
        picker.show(urls: unrouted, at: point)
    }

    /// Finder or Spotlight is the only way an agent app is opened on purpose.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindow.shared.show(model: model)
        return true
    }

    /// An agent app that never got the handler looks exactly like one that is
    /// working, so the icon carries that state rather than a line in the menu.
    private func refreshStatusIcon() {
        let symbol = NSImage(
            systemSymbolName: "arrow.triangle.branch",
            accessibilityDescription: model.isDefaultBrowser
                ? "OpenWith" : "OpenWith, not the default browser"
        )
        statusItem?.button?.image =
            model.isDefaultBrowser
            ? symbol
            : symbol?.withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
    }

    /// Re-arms itself, so the icon also catches a claim made from Settings.
    private func observeSetupState() {
        withObservationTracking {
            _ = model.isDefaultBrowser
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshStatusIcon()
                self?.observeSetupState()
            }
        }
    }

    @objc private func toggleAlwaysAsk() {
        model.alwaysAsk.toggle()
    }

    @objc private func toggleOpenAtLogin() {
        model.setOpenAtLogin(!model.openAtLogin)
    }

    @objc private func claimDefaultBrowser() {
        Task { await model.claimDefaultBrowser() }
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show(model: model)
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Rebuilt on every open: both states can change in System Settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        model.refresh()
        menu.removeAllItems()

        if !model.isDefaultBrowser {
            let claim = item("Set as Default Browser", #selector(claimDefaultBrowser))
            claim.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
            menu.addItem(claim)
            menu.addItem(.separator())
        }

        menu.addItem(
            item("Always Show the Picker", #selector(toggleAlwaysAsk), checked: model.alwaysAsk)
        )
        menu.addItem(
            item("Open at Login", #selector(toggleOpenAtLogin), checked: model.openAtLogin)
        )
        menu.addItem(.separator())

        let settings = item("Settings…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)

        let quit = item("Quit OpenWith", #selector(NSApplication.terminate(_:)))
        quit.target = nil
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = checked ? .on : .off
        return item
    }
}
