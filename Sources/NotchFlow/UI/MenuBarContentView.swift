import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: NotchFlowAppModel
    @ObservedObject private var nowPlaying: NowPlayingService
    @ObservedObject private var panelController: NotchPanelController
    @ObservedObject private var wallpaper: WallpaperRefreshService

    init(model: NotchFlowAppModel) {
        _model = ObservedObject(wrappedValue: model)
        _nowPlaying = ObservedObject(wrappedValue: model.nowPlaying)
        _panelController = ObservedObject(wrappedValue: model.panelController)
        _wallpaper = ObservedObject(wrappedValue: model.wallpaper)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NotchFlow")
                    .font(.headline)

                if let displayTitle = nowPlaying.snapshot.displayTitle {
                    Text(displayTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Divider()

            Button {
                model.togglePanelPinState()
            } label: {
                Label(
                    panelController.isPinned ? "收起面板" : "展开面板",
                    systemImage: panelController.isPinned ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
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
            .disabled(wallpaper.isRefreshing)

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
