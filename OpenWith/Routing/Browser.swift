import AppKit

/// An installed browser OpenWith can hand a URL to, identified by bundle id so
/// a rule survives the app being moved or updated.
struct Browser: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let appURL: URL

    init?(appURL: URL) {
        guard let bundle = Bundle(url: appURL), let id = bundle.bundleIdentifier else {
            return nil
        }
        self.id = id
        self.appURL = appURL
        // Not `FileManager.displayName`: it appends ".app" when Finder is set
        // to show all extensions.
        name =
            bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
            ?? appURL.deletingPathExtension().lastPathComponent
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: appURL.path)
    }

    /// Flag that opens a private window, or nil when the browser has none.
    /// Safari is the notable nil, so ⇧ stays inert there rather than quietly
    /// opening a normal window.
    var privateArgument: String? {
        let id = id.lowercased()
        return Self.privateArguments.first { id.hasPrefix($0.prefix) }?.flag
    }

    /// Prefix-matched so channel variants (Chrome Beta, Edge Dev) inherit.
    private static let privateArguments: [(prefix: String, flag: String)] = [
        ("com.google.chrome", "--incognito"),
        ("com.brave.browser", "--incognito"),
        ("com.coccoc.coccoc", "--incognito"),
        ("org.chromium.chromium", "--incognito"),
        ("com.vivaldi.vivaldi", "--incognito"),
        ("com.microsoft.edgemac", "--inprivate"),
        ("com.operasoftware.opera", "--private"),
        ("org.mozilla.firefox", "--private-window"),
        ("app.zen-browser.zen", "--private-window"),
        ("io.gitlab.librewolf", "--private-window"),
    ]
}
