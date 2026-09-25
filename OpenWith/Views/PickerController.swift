import AppKit
import SwiftUI

@MainActor
@Observable
final class PickerState {
    let urls: [URL]
    let browsers: [Browser]
    /// nil hides the remember toggle rather than offering a meaningless key.
    let domain: String?
    var remember = false
    var isPrivate = false

    init(urls: [URL], browsers: [Browser], domain: String?) {
        self.urls = urls
        self.browsers = browsers
        self.domain = domain
    }

    var displayURL: String {
        guard let first = urls.first else { return "" }
        var text = first.absoluteString
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
            text = String(text.dropFirst(scheme.count))
        }
        return urls.count > 1 ? "\(text)  +\(urls.count - 1) more" : text
    }

    var supportsPrivate: Bool {
        browsers.contains { $0.privateArgument != nil }
    }
}

/// Shows the browser picker at the pointer and turns the choice into a launch.
@MainActor
final class PickerController: NSObject {
    private let model: AppModel
    private var panel: PickerPanel?
    private var state: PickerState?
    private var monitors: [Any] = []

    init(model: AppModel) {
        self.model = model
    }

    func show(urls: [URL], at point: NSPoint) {
        dismiss()
        model.refresh()

        let browsers = model.pickerBrowsers
        guard !browsers.isEmpty else {
            presentNoBrowsers()
            return
        }

        let state = PickerState(
            urls: urls,
            browsers: browsers,
            domain: Self.sharedDomain(of: urls)
        )
        // Seeded, not just tracked: `flagsChanged` only reports a change, and
        // ⇧ is usually already down by the time the panel opens.
        state.isPrivate = NSEvent.modifierFlags.contains(.shift)
        self.state = state

        let hosting = NSHostingView(
            rootView: PickerView(
                state: state,
                onChoose: { [weak self] in self?.choose($0) },
                onCopy: { [weak self] in self?.copyAndClose() },
                onCancel: { [weak self] in self?.cancel() }
            )
        )
        hosting.layoutSubtreeIfNeeded()

        let panel = PickerPanel(contentView: hosting)
        panel.delegate = self
        panel.setFrame(
            Self.frame(
                for: hosting.fittingSize,
                at: point,
                in: Self.visibleFrame(containing: point)
            ),
            display: false
        )
        self.panel = panel

        // Without activating, the panel sits behind the focus of whatever app
        // the link was clicked in and the shortcuts never arrive.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    /// Only when the whole batch agrees: one choice covers every URL, so the
    /// first one's domain would save a rule the user never saw.
    private static func sharedDomain(of urls: [URL]) -> String? {
        let keys = Set(urls.compactMap(DomainKey.key(for:)))
        guard keys.count == 1, urls.allSatisfy({ DomainKey.key(for: $0) != nil }) else {
            return nil
        }
        return keys.first
    }

    func dismiss() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        state = nil
    }

    // MARK: Placement

    /// Below and right of the pointer, then pulled back inside the screen.
    /// Cocoa coordinates start bottom left, so "below" subtracts from y.
    static func frame(for size: NSSize, at point: NSPoint, in visible: NSRect) -> NSRect {
        let gap = 12.0
        let margin = 8.0
        var origin = NSPoint(x: point.x + gap, y: point.y - gap - size.height)

        if origin.x + size.width > visible.maxX - margin {
            origin.x = point.x - gap - size.width
        }
        if origin.y < visible.minY + margin {
            origin.y = point.y + gap
        }
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - margin - size.width)
        origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - margin - size.height)
        return NSRect(origin: origin, size: size)
    }

    static func visibleFrame(containing point: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    // MARK: Actions

    private func choose(_ browser: Browser) {
        guard let state else { return }
        if state.remember, let domain = state.domain {
            model.remember(domain: domain, browserID: browser.id)
        }
        Launcher.open(state.urls, in: browser, isPrivate: state.isPrivate)
        dismiss()
    }

    private func copyAndClose() {
        guard let state else { return }
        Launcher.copy(state.urls)
        cancel()
    }

    private func cancel() {
        guard panel != nil else { return }
        dismiss()
        // Deactivate, not `hide`: hiding puts the whole app away, so the next
        // `activate` drags an unhidden Settings window up with the picker.
        NSApp.deactivate()
    }

    private func presentNoBrowsers() {
        let alert = NSAlert()
        alert.messageText = "No other browser found"
        alert.informativeText = """
            OpenWith is the default handler for web links but there is no other \
            browser installed to hand them to.
            """
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }

    // MARK: Events

    /// Monitor callbacks run off the main actor and `NSEvent` is not `Sendable`,
    /// so only plain values cross.
    private struct KeyPress: Sendable {
        let code: UInt16
        let flags: NSEvent.ModifierFlags
        let characters: String?
    }

    private func installMonitors() {
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let press = KeyPress(
                code: event.keyCode,
                flags: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
                characters: event.charactersIgnoringModifiers
            )
            let consumed = MainActor.assumeIsolated { self?.handle(press) ?? false }
            return consumed ? nil : event
        }
        let flags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let isPrivate = event.modifierFlags.contains(.shift)
            MainActor.assumeIsolated { self?.state?.isPrivate = isPrivate }
            return event
        }
        let outside = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
        monitors = [keys, flags, outside].compactMap(\.self)
    }

    /// Returns true when the picker consumed the key.
    private func handle(_ press: KeyPress) -> Bool {
        guard let state else { return false }

        if press.flags == .command, press.characters?.lowercased() == "c" {
            copyAndClose()
            return true
        }
        // ⇧ is the private-window modifier, so it rides along. Anything else
        // belongs to the system: swallowing ⌘1 here would eat it silently.
        guard press.flags.subtracting(.shift).isEmpty else { return false }

        if press.code == 53 {
            cancel()
            return true
        }
        if press.code == 36 {
            choose(state.browsers[0])
            return true
        }
        guard let digit = Self.digit(in: press), digit <= state.browsers.count else {
            return false
        }
        choose(state.browsers[digit - 1])
        return true
    }

    /// `charactersIgnoringModifiers` still applies Shift, so a ⇧-held "1" reads
    /// as "!" and private mode would kill every digit. Key codes survive it.
    private static func digit(in press: KeyPress) -> Int? {
        if let text = press.characters, let digit = Int(text), digit > 0 {
            return digit
        }
        return digitKeyCodes[press.code]
    }

    private static let digitKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9,
    ]
}

extension PickerController: NSWindowDelegate {
    /// ⌘-Tab, or a click the global monitor missed, still has to close it.
    func windowDidResignKey(_ notification: Notification) {
        cancel()
    }
}
