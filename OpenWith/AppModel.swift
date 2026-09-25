import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    /// Show the picker even when a rule matches. Off by default: with no rules
    /// saved the picker comes up for every link anyway.
    var alwaysAsk = false {
        didSet { UserDefaults.standard.set(alwaysAsk, forKey: DefaultsKey.alwaysAsk) }
    }

    private(set) var rules: [Rule] = []
    private(set) var installedBrowsers: [Browser] = []
    private(set) var hiddenBrowserIDs: Set<String> = []
    private(set) var browserOrder: [String] = []
    private(set) var isDefaultBrowser = false
    /// Named in the UI, so "not default" says where links are going instead.
    private(set) var currentDefault: Browser?
    private(set) var openAtLogin = false
    /// Claiming the handler and registering the login item can both be refused
    /// by the system, and Settings is where that has to surface.
    private(set) var lastError: String?

    private enum DefaultsKey {
        static let alwaysAsk = "AlwaysAsk"
        static let rules = "Rules"
        static let hiddenBrowsers = "HiddenBrowsers"
        static let browserOrder = "BrowserOrder"
        static let didOnboard = "DidOnboard"
    }

    /// True once, ever. A login item that nagged about the handler every
    /// morning would be worse than an idle icon, so the menu carries it after.
    static func consumeFirstLaunch() -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.didOnboard) else { return false }
        defaults.set(true, forKey: DefaultsKey.didOnboard)
        return true
    }

    init() {
        let defaults = UserDefaults.standard
        _alwaysAsk = defaults.bool(forKey: DefaultsKey.alwaysAsk)
        _hiddenBrowserIDs = Set(defaults.stringArray(forKey: DefaultsKey.hiddenBrowsers) ?? [])
        _browserOrder = defaults.stringArray(forKey: DefaultsKey.browserOrder) ?? []
        if let data = defaults.data(forKey: DefaultsKey.rules) {
            _rules = (try? JSONDecoder().decode([Rule].self, from: data)) ?? []
        }

        refresh()
    }

    /// Re-reads what lives outside the app: browsers, the handler and the login
    /// item all change in System Settings while OpenWith sits in the background.
    func refresh() {
        installedBrowsers = BrowserRegistry.installed()
        currentDefault = DefaultBrowser.current
        isDefaultBrowser = DefaultBrowser.isCurrent
        openAtLogin = LoginItem.isEnabled
    }

    // MARK: Browsers

    /// In the order the user arranged. Ones not yet seen land at the end, so a
    /// new install never reshuffles shortcuts already learned.
    var orderedBrowsers: [Browser] {
        let rank = Dictionary(
            browserOrder.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return installedBrowsers.enumerated()
            .sorted { lhs, rhs in
                let left = rank[lhs.element.id] ?? browserOrder.count + lhs.offset
                let right = rank[rhs.element.id] ?? browserOrder.count + rhs.offset
                return left < right
            }
            .map(\.element)
    }

    /// What the picker shows, which is also what the number keys index into.
    var pickerBrowsers: [Browser] {
        orderedBrowsers.filter { !hiddenBrowserIDs.contains($0.id) }
    }

    func isHidden(_ browser: Browser) -> Bool {
        hiddenBrowserIDs.contains(browser.id)
    }

    func setHidden(_ hidden: Bool, for browser: Browser) {
        if hidden {
            hiddenBrowserIDs.insert(browser.id)
        } else {
            hiddenBrowserIDs.remove(browser.id)
        }
        UserDefaults.standard.set(Array(hiddenBrowserIDs), forKey: DefaultsKey.hiddenBrowsers)
    }

    func moveBrowsers(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = orderedBrowsers.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        // Ids missing from `orderedBrowsers` are browsers not installed right
        // now; carrying them keeps a reinstall out of the bottom of the list.
        browserOrder = ids + browserOrder.filter { !ids.contains($0) }
        UserDefaults.standard.set(browserOrder, forKey: DefaultsKey.browserOrder)
    }

    // MARK: Rules

    /// nil when the picker should come up.
    func route(_ url: URL) -> Browser? {
        guard !alwaysAsk, let host = url.host()?.lowercased() else { return nil }
        // Longest matching domain wins, so a rule on gist.github.com can carve
        // itself out of a broader github.com rule.
        guard
            let rule =
                rules
                .filter({ DomainKey.matches(rule: $0.domain, host: host) })
                .max(by: { $0.domain.count < $1.domain.count })
        else { return nil }
        return installedBrowsers.first { $0.id == rule.browserID }
    }

    func remember(domain: String, browserID: String) {
        rules.removeAll { $0.domain == domain }
        rules.append(Rule(domain: domain, browserID: browserID))
        sortAndPersistRules()
    }

    func removeRules(_ domains: Set<String>) {
        rules.removeAll { domains.contains($0.domain) }
        sortAndPersistRules()
    }

    func updateRule(_ domain: String, browserID: String) {
        guard let index = rules.firstIndex(where: { $0.domain == domain }) else { return }
        rules[index].browserID = browserID
        sortAndPersistRules()
    }

    private func sortAndPersistRules() {
        rules.sort { $0.domain.localizedStandardCompare($1.domain) == .orderedAscending }
        UserDefaults.standard.set(try? JSONEncoder().encode(rules), forKey: DefaultsKey.rules)
    }

    // MARK: System state

    func setOpenAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        // Read back rather than trusting the call, so a refused registration
        // does not leave the switch showing a state the system never took.
        openAtLogin = LoginItem.isEnabled
    }

    func claimDefaultBrowser() async {
        await apply { try await DefaultBrowser.claim() }
    }

    func restorePreviousDefaultBrowser() async {
        await apply { try await DefaultBrowser.restorePrevious() }
    }

    private func apply(_ change: () async throws -> Void) async {
        do {
            try await change()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        currentDefault = DefaultBrowser.current
        isDefaultBrowser = DefaultBrowser.isCurrent
    }
}
