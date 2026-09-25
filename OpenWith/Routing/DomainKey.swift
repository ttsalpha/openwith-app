import Foundation

/// The string a rule is keyed by, and whether a saved key covers a host.
/// Pure by design: no AppKit, no state.
enum DomainKey {
    /// The host exactly as the URL spells it. Shortening it to a registrable
    /// domain takes the Public Suffix List to get right, and a hand-written
    /// stand-in guesses wrong on ccTLDs, widening the rule without saying so.
    /// The Rules tab is where a key gets shortened, deliberately.
    static func key(for url: URL) -> String? {
        guard let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        // `www.` is an alias everywhere rather than a guess about one registry.
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return bare.isEmpty ? host : bare
    }

    /// A rule covers its own host and everything under it, so `github.com`
    /// catches `gist.github.com` without a second rule.
    static func matches(rule: String, host: String) -> Bool {
        let rule = rule.lowercased()
        let host = host.lowercased()
        return host == rule || host.hasSuffix("." + rule)
    }
}
