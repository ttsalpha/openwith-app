import AppKit
import SwiftUI

struct SettingsPane: View {
    let tab: SettingsTab

    var body: some View {
        switch tab {
        case .general: GeneralSettings().frame(width: 540, height: 320)
        case .browsers: BrowsersSettings().frame(width: 540, height: 404)
        case .rules: RulesSettings().frame(width: 540, height: 404)
        case .about: AboutSettings().frame(width: 540, height: 326)
        }
    }
}

// MARK: General

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                DefaultBrowserRow()
            } footer: {
                Footnote(
                    """
                    Links clicked inside a browser never leave it, so they never reach OpenWith. \
                    Only links from other apps do: Mail, Slack, Notes, a terminal.
                    """
                )
            }

            Section {
                Toggle("Always show the picker, even when a rule matches", isOn: $model.alwaysAsk)
                Toggle("Apply rules to subdomains", isOn: $model.matchSubdomains)
                Toggle(
                    "Open at Login",
                    isOn: Binding(get: { model.openAtLogin }, set: model.setOpenAtLogin)
                )
            } footer: {
                Footnote(
                    """
                    Hold ⌥ while clicking a link to show the picker for that one link. \
                    With subdomains applied, a rule on github.com also covers \
                    gist.github.com.
                    """
                )
            }

            if let error = model.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DefaultBrowserRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(
                systemName: model.isDefaultBrowser
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.system(size: 20))
            .foregroundStyle(model.isDefaultBrowser ? .green : .orange)
            .frame(height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.isDefaultBrowser ? "Handling web links" : "Not the default browser")
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if model.isDefaultBrowser {
                if let previous = DefaultBrowser.previous {
                    Button("Restore \(previous.name)") {
                        Task { await model.restorePreviousDefaultBrowser() }
                    }
                }
            } else {
                Button("Set as Default") {
                    Task { await model.claimDefaultBrowser() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        guard !model.isDefaultBrowser else {
            return "Links from other apps open the picker."
        }
        let holder = model.currentDefault?.name ?? "another browser"
        return "Links keep opening straight in \(holder)."
    }
}

// MARK: Browsers

struct BrowsersSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            List {
                ForEach(model.orderedBrowsers) { browser in
                    BrowserRow(browser: browser, shortcut: shortcut(for: browser))
                }
                .onMove(perform: model.moveBrowsers)
            }
            .scrollContentBackground(.hidden)
            .background(.quinary, in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5)
            )

            Footnote(
                """
                Drag to reorder: the order is what the 1…9 keys pick. Anything registered to open \
                https shows up here, browser or not.
                """
            )
        }
        .padding(20)
    }

    private func shortcut(for browser: Browser) -> Int? {
        guard let index = model.pickerBrowsers.firstIndex(where: { $0.id == browser.id }),
            index < 9
        else { return nil }
        return index + 1
    }
}

private struct BrowserRow: View {
    @Environment(AppModel.self) private var model
    let browser: Browser
    let shortcut: Int?

    var body: some View {
        HStack(spacing: 10) {
            Toggle(
                isOn: Binding(
                    get: { !model.isHidden(browser) },
                    set: { model.setHidden(!$0, for: browser) }
                )
            ) {
                EmptyView()
            }
            .labelsHidden()

            Image(nsImage: browser.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 0) {
                Text(browser.name)
                if browser.privateArgument == nil {
                    Text("No private window")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .opacity(model.isHidden(browser) ? 0.45 : 1)

            Spacer(minLength: 8)

            if let shortcut {
                KeyCap("\(shortcut)")
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: Rules

struct RulesSettings: View {
    @Environment(AppModel.self) private var model

    @State private var draft = ""
    @State private var draftBrowser = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if model.rules.isEmpty {
                    ContentUnavailableView {
                        Label("No rules yet", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Tick Remember in the picker, or add a domain below.")
                    }
                } else {
                    List {
                        ForEach(model.rules) { rule in
                            RuleRow(rule: rule)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(.quinary, in: .rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                TextField("e.g. github.com", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .onChange(of: draft) { _, _ in error = nil }
                BrowserPicker(selection: $draftBrowser)
                Button("Add", action: add)
            }

            HStack {
                // The hint line doubles as the error line so nothing shifts.
                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Footnote("The longest matching rule wins.")
                }
                Spacer(minLength: 12)
                Button("Remove All") {
                    model.removeRules(Set(model.rules.map(\.domain)))
                }
                .disabled(model.rules.isEmpty)
            }
        }
        .padding(20)
        .onAppear {
            if draftBrowser.isEmpty { draftBrowser = model.orderedBrowsers.first?.id ?? "" }
        }
    }

    /// Add stays enabled and says what is wrong, rather than greying out and
    /// leaving the reason to be guessed.
    private func add() {
        guard let key = DomainKey.key(forInput: draft) else {
            error =
                draft.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Type a domain first." : "Not a domain."
            return
        }
        guard !model.rules.contains(where: { $0.domain == key }) else {
            error = "\(key) already has a rule."
            return
        }
        guard !draftBrowser.isEmpty else {
            error = "No browser to send it to."
            return
        }
        model.addRule(key, browserID: draftBrowser)
        draft = ""
        error = nil
    }
}

private struct RuleRow: View {
    @Environment(AppModel.self) private var model
    let rule: Rule

    @State private var domain: String
    @FocusState private var isEditing: Bool
    @State private var isHovering = false

    init(rule: Rule) {
        self.rule = rule
        _domain = State(initialValue: rule.domain)
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField("", text: $domain)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .focused($isEditing)
                .onSubmit(commit)
                .onChange(of: isEditing) { _, editing in
                    if !editing { commit() }
                }

            Spacer(minLength: 12)

            if let browser = model.installedBrowsers.first(where: { $0.id == rule.browserID }) {
                Image(nsImage: browser.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            }

            BrowserPicker(
                selection: Binding(
                    get: { rule.browserID },
                    set: { model.updateRule(rule.domain, browserID: $0) }
                ),
                missing: rule.browserID
            )

            Button {
                model.removeRules([rule.domain])
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(isHovering ? Color.red : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.borderless)
            .help("Remove this rule")
        }
        .padding(.vertical, 3)
        .onHover { isHovering = $0 }
    }

    /// Refused edits snap back, since the alternative is a field showing a key
    /// that was never stored. Typing `www.github.com` over `github.com` is not
    /// a refusal though: it normalises to what is already there.
    private func commit() {
        guard let key = DomainKey.key(forInput: domain) else {
            domain = rule.domain
            return
        }
        guard key != rule.domain else {
            domain = key
            return
        }
        if model.renameRule(rule.domain, to: key) == nil {
            domain = rule.domain
        }
    }
}

private struct BrowserPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String
    var missing: String?

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(model.orderedBrowsers) { browser in
                Text(browser.name).tag(browser.id)
            }
            if let missing, !model.orderedBrowsers.contains(where: { $0.id == missing }) {
                Text("Not installed").tag(missing)
            }
        }
        .labelsHidden()
        .frame(width: 150)
    }
}

// MARK: About

struct AboutSettings: View {
    private static let repo = "https://github.com/ttsalpha/openwith-app"

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 128, height: 128)

            Text("OpenWith")
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 4)
            Text(Self.version)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(
                """
                macOS gives you one default browser. OpenWith makes itself that \
                browser, then asks you where each link should actually go, in a \
                picker that opens under the pointer.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 400)
            .padding(.top, 10)

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                Link("Author", destination: URL(string: "https://ttsalpha.com")!)
                Text("·").foregroundStyle(.tertiary)
                Link("GitHub", destination: URL(string: Self.repo)!)
                Text("·").foregroundStyle(.tertiary)
                Link("MIT License", destination: URL(string: "\(Self.repo)/blob/main/LICENSE")!)
            }
            .font(.callout)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }
}

// MARK: Shared

private struct Footnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct KeyCap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 18)
            .background(.quaternary, in: .rect(cornerRadius: 4))
    }
}
