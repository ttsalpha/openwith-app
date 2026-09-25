import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, browsers, rules, about

    var title: String {
        switch self {
        case .general: "General"
        case .browsers: "Browsers"
        case .rules: "Rules"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .browsers: "macwindow.on.rectangle"
        case .rules: "list.bullet.rectangle"
        case .about: "info.circle"
        }
    }

    var identifier: NSToolbarItem.Identifier { .init(rawValue) }
}

/// SwiftUI's `Settings` scene only opens from a `SettingsLink` inside a view,
/// and OpenWith's only entry point is a status-bar `NSMenu`. Owning the window
/// here keeps that a plain menu action and allows `toolbarStyle = .preference`,
/// the tab strip every other Mac settings window uses.
@MainActor
final class SettingsWindow: NSObject {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    private var model: AppModel?
    private var tab = SettingsTab.general

    func show(model: AppModel) {
        model.refresh()
        self.model = model

        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false

            let toolbar = NSToolbar(identifier: "Settings")
            toolbar.delegate = self
            toolbar.allowsUserCustomization = false
            toolbar.displayMode = .iconAndLabel
            window.toolbar = toolbar

            self.window = window
            install(tab, reanchor: false)
            window.center()
        }

        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    @objc private func selectTab(_ sender: NSToolbarItem) {
        guard let tab = SettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
        install(tab, reanchor: true)
    }

    /// Each pane declares its own size and the window follows, rather than
    /// padding every tab to the tallest. Re-anchoring keeps the title bar still.
    private func install(_ tab: SettingsTab, reanchor: Bool) {
        guard let window, let model else { return }
        self.tab = tab
        window.title = tab.title
        window.toolbar?.selectedItemIdentifier = tab.identifier

        let controller = NSHostingController(rootView: SettingsPane(tab: tab).environment(model))
        let size = controller.view.fittingSize
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)

        window.contentViewController = controller
        window.setContentSize(size)
        if reanchor {
            window.setFrameTopLeftPoint(topLeft)
        }
    }
}

extension SettingsWindow: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.identifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: identifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }
}
