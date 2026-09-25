import AppKit

enum BrowserRegistry {
    private static let probe = URL(string: "https://example.com")!

    /// Every app Launch Services will hand an https URL to, in its ranking,
    /// which puts the browsers actually in use ahead of an alphabetical sort.
    ///
    /// Excluding ourselves is not cosmetic: OpenWith is the default handler, so
    /// offering it as a target would route the click back into this picker. The
    /// list also holds apps that are not browsers, since anything may register
    /// the scheme; Settings hides those rather than this guessing.
    static func installed() -> [Browser] {
        let mine = Bundle.main.bundleIdentifier?.lowercased()
        var seen: Set<String> = []
        return NSWorkspace.shared.urlsForApplications(toOpen: probe)
            .compactMap(Browser.init(appURL:))
            .filter { browser in
                // Launch Services lists every copy on disk. Two copies share
                // one bundle id, which rules key off and shortcuts count from.
                let id = browser.id.lowercased()
                return id != mine && seen.insert(id).inserted
            }
    }
}
