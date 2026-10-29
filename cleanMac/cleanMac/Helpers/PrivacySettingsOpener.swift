import AppKit

enum PrivacySettingsOpener {
    @MainActor
    static func openLoginItems() -> Bool {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"), NSWorkspace.shared.open(url) { return true }
        return NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    @MainActor
    static func openAppManagement() -> Bool {
        let destinations = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AppBundles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles"
        ]
        for destination in destinations {
            if let url = URL(string: destination), NSWorkspace.shared.open(url) {
                return true
            }
        }
        return false
    }
}
