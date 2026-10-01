import Foundation

/// How a rule is keyed and matched. Pure: no AppKit, no state.
enum DomainKey {
    /// The host the URL names. Shortening it to a registrable domain needs the
    /// Public Suffix List; a hand-written stand-in guesses wrong on ccTLDs.
    static func key(for url: URL) -> String? {
        guard let host = url.host(), isValid(host) else { return nil }
        return bare(host)
    }

    /// Takes what a person types into the Rules tab, a pasted URL as often as a
    /// bare host.
    static func key(forInput input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if let url = URL(string: text), url.host() != nil { return key(for: url) }
        guard let url = URL(string: "https://\(text)") else { return nil }
        return key(for: url)
    }

    /// A rule always matches the host it names. Whether it reaches below that is
    /// one setting for all rules, not something spelled into each key.
    static func matches(rule: String, host: String, includingSubdomains: Bool) -> Bool {
        let rule = rule.lowercased()
        let host = bare(host)
        if host == rule { return true }
        return includingSubdomains && host.hasSuffix("." + rule)
    }

    /// `www.` is an alias everywhere. Both sides of a match have to drop it, or
    /// a rule saved from a www URL stops firing once subdomains are off.
    private static func bare(_ host: String) -> String {
        let host = host.lowercased()
        guard host.hasPrefix("www."), host.count > 4 else { return host }
        return String(host.dropFirst(4))
    }

    /// URL parsing returns hosts no rule can ever match: a leading dot, an empty
    /// label, a stray `*`. They would persist as a rule that routes nothing.
    ///
    /// A dot is required for the same reason a browser treats a bare word in the
    /// address bar as a search: `aa` is a typo, not a host. `localhost` is the
    /// one name common enough to keep.
    private static func isValid(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253 else { return false }
        guard host.contains(".") || host == "localhost" else { return false }
        return host.split(separator: ".", omittingEmptySubsequences: false)
            .allSatisfy { label in
                !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                    && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
            }
    }
}
