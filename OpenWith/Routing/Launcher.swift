import AppKit

/// Hands URLs to one specific browser, always naming the target app: OpenWith
/// is the default handler, so a bare `NSWorkspace.open(url)` would loop back in.
enum Launcher {
    static func open(_ urls: [URL], in browser: Browser, isPrivate: Bool) {
        guard let flag = browser.privateArgument, isPrivate else {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(urls, withApplicationAt: browser.appURL, configuration: config)
            return
        }
        openPrivate(urls, in: browser, flag: flag)
    }

    /// `arguments` only applies to a new instance, hence
    /// `createsNewApplicationInstance`. Chromium and Firefox forward that
    /// command line to the running instance and exit, which is what lands the
    /// window in the session on screen: `open -na Chrome --args --incognito`.
    ///
    /// The URLs ride in `arguments`, not `open(_:)`, or they open twice.
    private static func openPrivate(_ urls: [URL], in browser: Browser, flag: String) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = true
        config.arguments = [flag] + urls.map(\.absoluteString)
        NSWorkspace.shared.openApplication(at: browser.appURL, configuration: config)
    }

    static func copy(_ urls: [URL]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            urls.map(\.absoluteString).joined(separator: "\n"),
            forType: .string
        )
    }
}
