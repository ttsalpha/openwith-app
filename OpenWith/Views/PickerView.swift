import AppKit
import SwiftUI

struct PickerView: View {
    @Bindable var state: PickerState
    let onChoose: (Browser) -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.displayURL)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 340, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(Array(state.browsers.enumerated()), id: \.element.id) { index, browser in
                    BrowserButton(
                        browser: browser,
                        shortcut: index < 9 ? index + 1 : nil,
                        isPrivate: state.isPrivate && browser.privateArgument != nil,
                        action: { onChoose(browser) }
                    )
                }
            }

            Divider()

            HStack(spacing: 10) {
                if let domain = state.domain {
                    Toggle(isOn: $state.remember) {
                        Text("Remember \(domain)").font(.system(size: 11))
                    }
                    .toggleStyle(.checkbox)
                }
                Spacer(minLength: 8)
                Button(action: onCopy) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.link)
            }

            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: 0.5))
        .clipShape(shape)
        .onExitCommand(perform: onCancel)
    }

    private var hint: String {
        var parts: [String] = []
        let reachable = min(state.browsers.count, 9)
        if reachable > 1 { parts.append("1…\(reachable) open") }
        if state.supportsPrivate { parts.append("⇧ private") }
        parts.append("⎋ cancel")
        return parts.joined(separator: "  ·  ")
    }
}

private struct BrowserButton: View {
    let browser: Browser
    let shortcut: Int?
    let isPrivate: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(nsImage: browser.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .topLeading) {
                        if let shortcut {
                            badge(Text("\(shortcut)"), offset: CGSize(width: -4, height: -4))
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isPrivate {
                            badge(
                                Text(Image(systemName: "eye.slash.fill")),
                                offset: CGSize(width: 4, height: 4)
                            )
                        }
                    }
                Text(browser.name)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 84)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(isHovering ? 1 : 0), in: .rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private func badge(_ content: Text, offset: CGSize) -> some View {
        content
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(Circle().fill(.black.opacity(0.7)))
            .offset(x: offset.width, y: offset.height)
    }
}
