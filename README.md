<h1 align="center">
  <img src="OpenWith/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" width="150" alt=""><br>
  OpenWith
</h1>

macOS gives you one default browser. OpenWith makes itself that browser, then asks you where each
link should actually go, in a picker that opens under the pointer.

## Requirements

- macOS 14 or later. Built and run on macOS 27, Apple Silicon.
- Xcode with the macOS SDK. Swift 6.

## What it does

| | |
| --- | --- |
| Picker at the pointer | macOS never tells an app where a link sat inside another app, so the panel opens at the cursor, which is where the click was |
| Remember a site | Keyed on the exact host, covering everything under it, so a rule on `github.com` catches `gist.github.com`. Longest match wins; widen a key in Settings |
| `1`…`9`, `⎋`, `⌘C`, `⏎` | Pick by number, cancel, copy the link, or take the first browser |
| Hold `⇧` | Opens a private window, for browsers that have a flag for one. Safari has none, so it stays inert there rather than quietly opening a normal window |
| Hold `⌥` while clicking a link | Shows the picker even when a rule already matches |
| Open at Login | `SMAppService`, which keys off the bundle path: the app has to live in /Applications |
| Browser list | Whatever Launch Services registers for `https`, so a terminal can turn up in it. Hide those in Settings |

## Build and run

```sh
xcodebuild -project OpenWith.xcodeproj -scheme OpenWith -configuration Debug \
  -destination 'platform=macOS' build
cp -R ~/Library/Developer/Xcode/DerivedData/OpenWith-*/Build/Products/Debug/OpenWith.app /Applications/
open /Applications/OpenWith.app
```

It is an agent app (`LSUIElement`): no Dock icon, no window, just the status item. Nothing reaches
it until you pick **Set as Default Browser** from that menu and accept the system prompt.

To check the handler took:

```sh
defaults read com.apple.LaunchServices/com.apple.launchservices.secure \
  | grep -A2 'LSHandlerURLScheme = https'
```

## Layout

```
OpenWith/
  AppDelegate.swift     Status item, menu, and the entry point every URL arrives through
  AppModel.swift        Prefs, rules, browser order, and the routing decision
  Info.plist            CFBundleURLTypes only; everything else is generated
  Routing/              Browser discovery, domain keys, and the launch itself
  System/               Default-handler and login-item wrappers
  Views/                The picker panel and the Settings window
```

## License

[MIT](LICENSE) by [ttsalpha](https://ttsalpha.com)
