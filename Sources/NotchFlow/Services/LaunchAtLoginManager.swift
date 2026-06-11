import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage = "Ready"

    var isSupported: Bool {
        true
    }

    func refreshStatus() async {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        statusMessage = Self.description(for: status)
    }

    func setEnabled(_ enabled: Bool) async {
        isWorking = true
        defer { isWorking = false }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try await SMAppService.mainApp.unregister()
            }

            await refreshStatus()
        } catch {
            statusMessage = "Unavailable in the current launch mode"
            await refreshStatus()
        }
    }

    private static func description(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Needs approval in Login Items"
        case .notFound:
            return "App bundle not found"
        case .notRegistered:
            return "Disabled"
        @unknown default:
            return "Unknown status"
        }
    }
}
