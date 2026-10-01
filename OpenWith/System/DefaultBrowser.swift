import AppKit

/// Reads and claims the system http/https handler.
enum DefaultBrowser {
    private static let previousKey = "PreviousDefaultBrowser"
    private static let probe = URL(string: "https://example.com")!

    static var current: Browser? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: probe) else { return nil }
        return Browser(appURL: url)
    }

    static var isCurrent: Bool {
        current?.id.lowercased() == Bundle.main.bundleIdentifier?.lowercased()
    }

    /// Whatever was default before OpenWith, so there is always a way back.
    static var previous: Browser? {
        guard let id = UserDefaults.standard.string(forKey: previousKey),
            let url = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id).first
        else { return nil }
        return Browser(appURL: url)
    }

    /// macOS puts up its own consent sheet. Both schemes get claimed, or plain
    /// http links keep going elsewhere.
    static func claim() async throws {
        if !isCurrent, let current = NSWorkspace.shared.urlForApplication(toOpen: probe),
            let id = Bundle(url: current)?.bundleIdentifier
        {
            UserDefaults.standard.set(id, forKey: previousKey)
        }
        try await set(Bundle.main.bundleURL)
    }

    static func restorePrevious() async throws {
        guard let previous else { return }
        try await set(previous.appURL)
    }

    private static func set(_ appURL: URL) async throws {
        let workspace = NSWorkspace.shared
        try await workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "http")
        try await workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: "https")
    }
}
