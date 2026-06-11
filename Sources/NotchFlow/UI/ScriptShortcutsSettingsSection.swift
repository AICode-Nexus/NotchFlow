import SwiftUI
import UniformTypeIdentifiers

struct ScriptShortcutsSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ScriptShortcutStore

    @State private var isDropTargeted = false
    @State private var isEditingShortcuts = false
    @State private var isImporterPresented = false
    @State private var draggedShortcutID: UUID?

    private let shortcutColumns = [
        GridItem(.adaptive(minimum: 86, maximum: 112), spacing: 12, alignment: .top),
    ]

    var body: some View {
        Section("快捷启动") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("布局")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Picker("快捷启动布局", selection: $settings.quickLaunchLayoutMode) {
                        ForEach(QuickLaunchLayoutMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("显示名称", isOn: $settings.quickLaunchShowsLabels)
                }

                Text("拖入 .app / .sh / .command / .scpt。App 会直接保存原路径，脚本会复制到应用目录，后续都能直接启动。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)

                            Text(isDropTargeted ? "松开即可导入快捷项" : "把 App 或脚本拖到这里")
                                .font(.subheadline.weight(.medium))

                            Text("支持 .app / .sh / .command / .scpt")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(height: 96)
                    .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)

                Button("选择 App 或脚本导入…") {
                    isImporterPresented = true
                }

                if store.shortcuts.isEmpty {
                    Text("还没有已保存快捷项")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("已保存 \(store.shortcuts.count) 个")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(isEditingShortcuts ? "完成" : "编辑") {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                isEditingShortcuts.toggle()
                                draggedShortcutID = nil
                            }
                        }
                    }

                    LazyVGrid(columns: shortcutColumns, alignment: .leading, spacing: 12) {
                        ForEach(store.shortcuts) { shortcut in
                            settingsShortcutTile(shortcut)
                        }
                    }
                }

                Text(store.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true,
                onCompletion: handleImportSelection
            )
        }
    }

    private func settingsShortcutTile(_ shortcut: ScriptShortcut) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 7) {
                settingsShortcutIcon(shortcut)

                Text(shortcut.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(shortcut.detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .top)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .rotationEffect(.degrees(shortcutJiggleAngle(for: shortcut)))
            .scaleEffect(draggedShortcutID == shortcut.id ? 1.04 : 1.0)
            .animation(shortcutJiggleAnimation(for: shortcut), value: isEditingShortcuts)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: draggedShortcutID)

            if isEditingShortcuts {
                settingsShortcutDeleteButton(shortcut)
                    .padding(3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            guard !isEditingShortcuts else {
                return
            }

            store.run(shortcut)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    enterShortcutEditing()
                }
        )
        .onDrag {
            enterShortcutEditing()
            draggedShortcutID = shortcut.id
            return NSItemProvider(object: shortcut.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: SettingsShortcutReorderDropDelegate(
                targetID: shortcut.id,
                draggedShortcutID: $draggedShortcutID,
                isEditing: $isEditingShortcuts,
                store: store
            )
        )
    }

    @ViewBuilder
    private func settingsShortcutIcon(_ shortcut: ScriptShortcut) -> some View {
        if let image = shortcut.iconImage {
            Image(nsImage: image)
                .resizable()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: shortcut.kind.symbolName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
        }
    }

    private func settingsShortcutDeleteButton(_ shortcut: ScriptShortcut) -> some View {
        Button(role: .destructive) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                store.remove(shortcut)

                if store.shortcuts.isEmpty {
                    isEditingShortcuts = false
                }
            }
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, Color.red)
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(0.9), in: Circle())
        }
        .buttonStyle(.plain)
        .help("移除快捷项")
    }

    private func enterShortcutEditing() {
        guard !isEditingShortcuts else {
            return
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
            isEditingShortcuts = true
        }
    }

    private func shortcutJiggleAngle(for shortcut: ScriptShortcut) -> Double {
        guard isEditingShortcuts else {
            return 0
        }

        return shortcutJiggleSeed(for: shortcut).isMultiple(of: 2) ? -1.5 : 1.5
    }

    private func shortcutJiggleAnimation(for shortcut: ScriptShortcut) -> Animation? {
        guard isEditingShortcuts else {
            return .easeOut(duration: 0.12)
        }

        return .easeInOut(duration: shortcutJiggleDuration(for: shortcut))
            .repeatForever(autoreverses: true)
    }

    private func shortcutJiggleDuration(for shortcut: ScriptShortcut) -> Double {
        let offset = Double(shortcutJiggleSeed(for: shortcut) % 3) * 0.025
        return 0.14 + offset
    }

    private func shortcutJiggleSeed(for shortcut: ScriptShortcut) -> Int {
        shortcut.id.uuidString.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            store.importScripts(at: urls)
        case .failure(let error):
            store.reportImportFailure(error)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        guard !fileProviders.isEmpty else {
            return false
        }

        for provider in fileProviders {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                if let error {
                    Task { @MainActor in
                        store.reportImportFailure(error)
                    }
                    return
                }

                guard let data,
                      let url = NSURL(absoluteURLWithDataRepresentation: data, relativeTo: nil) as URL? else {
                    return
                }

                Task { @MainActor in
                    store.importScripts(at: [url])
                }
            }
        }

        return true
    }
}

private struct SettingsShortcutReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedShortcutID: UUID?
    @Binding var isEditing: Bool
    let store: ScriptShortcutStore

    func dropEntered(info: DropInfo) {
        guard isEditing,
              let draggedShortcutID,
              draggedShortcutID != targetID
        else {
            return
        }

        _ = store.moveShortcut(id: draggedShortcutID, to: targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedShortcutID = nil
        store.completeReorder()
        return true
    }
}
