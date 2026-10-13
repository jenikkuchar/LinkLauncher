import Foundation
import ServiceManagement

/// Spouštění po přihlášení přes `SMAppService.mainApp`.
enum LoginItem {
    private static let autoEnabledKey = "didAutoEnableLoginItem"

    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isEnabled: Bool { status == .enabled }
    static var requiresApproval: Bool { status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard status != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard status != .notRegistered else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    /// Při prvním spuštění zapne spouštění po přihlášení automaticky.
    static func enableOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: autoEnabledKey) else { return }
        defaults.set(true, forKey: autoEnabledKey)
        do {
            try setEnabled(true)
        } catch {
            NSLog("LinkLauncher: nepodařilo se zapnout spouštění po přihlášení: \(error.localizedDescription)")
        }
    }
}
