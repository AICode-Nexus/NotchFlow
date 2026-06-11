import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: NotchFlowAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NotchFlow")
                    .font(.headline)

                Text(model.nowPlaying.snapshot.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()

            Button {
                model.togglePanelPinState()
            } label: {
                Label(
                    model.panelController.isPinned ? "收起面板" : "展开面板",
                    systemImage: model.panelController.isPinned ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
                )
            }

            Button {
                model.repositionPanel()
            } label: {
                Label("重新定位", systemImage: "scope")
            }

            Button {
                model.wallpaper.refreshOrChooseFolder()
            } label: {
                Label("刷新壁纸", systemImage: "photo.on.rectangle.angled")
            }
            .disabled(model.wallpaper.isRefreshing)

            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
        }
        .padding(12)
        .frame(width: 260)
    }
}
