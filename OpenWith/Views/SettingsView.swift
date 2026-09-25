import AppKit
import SwiftUI

struct SettingsPane: View {
    let tab: SettingsTab

    var body: some View {
        switch tab {
        case .general: GeneralSettings().frame(width: 540, height: 268)
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
                Toggle(
                    "Open at Login",
                    isOn: Binding(get: { model.openAtLogin }, set: model.setOpenAtLogin)
                )
            } footer: {
                Footnote(
                    "Hold ⌥ while clicking a link to do the same for just that one link."
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.rules.isEmpty {
                ContentUnavailableView {
                    Label("No rules yet", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Tick Remember in the picker to send a domain straight to one browser.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                HStack {
                    Footnote("A rule covers its subdomains. The longest match wins.")
                    Spacer(minLength: 12)
                    Button("Remove All") {
                        model.removeRules(Set(model.rules.map(\.domain)))
                    }
                }
            }
        }
        .padding(20)
    }
}

private struct RuleRow: View {
    @Environment(AppModel.self) private var model
    let rule: Rule

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(rule.domain)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            if let browser = model.installedBrowsers.first(where: { $0.id == rule.browserID }) {
                Image(nsImage: browser.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
            }

            Picker(
                "",
                selection: Binding(
                    get: { rule.browserID },
                    set: { model.updateRule(rule.domain, browserID: $0) }
                )
            ) {
                ForEach(model.orderedBrowsers) { browser in
                    Text(browser.name).tag(browser.id)
                }
                if !model.orderedBrowsers.contains(where: { $0.id == rule.browserID }) {
                    Text("Not installed").tag(rule.browserID)
                }
            }
            .labelsHidden()
            .frame(width: 150)

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
