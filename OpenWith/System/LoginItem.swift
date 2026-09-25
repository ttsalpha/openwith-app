import ServiceManagement

/// `SMAppService` keys off the bundle path, so a build launched out of
/// DerivedData registers that path and dies with it. The app has to live in
/// /Applications for this to mean anything.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
