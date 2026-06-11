import SwiftUI

@main
struct NotchFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = NotchFlowAppModel.shared

    var body: some Scene {
        MenuBarExtra("NotchFlow", systemImage: model.menuBarIconName) {
            MenuBarContentView(model: model)
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
