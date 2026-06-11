import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        DispatchQueue.main.async {
            NotchFlowAppModel.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotchFlowAppModel.shared.stop()
    }
}
