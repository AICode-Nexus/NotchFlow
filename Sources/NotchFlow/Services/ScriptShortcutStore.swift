import AppKit
import Foundation

@MainActor
final class ScriptShortcutStore: ObservableObject {
    private enum Keys {
        static let shortcuts = "ScriptShortcuts"
    }

    private enum StoreError: LocalizedError {
        case unsupportedFileExtension(String)
        case unsupportedItem(String)
        case terminalLaunchFailed(String)
        case itemMissing(String)
        case scriptsDirectoryUnavailable

        var errorDescription: String? {
            switch self {
            case .unsupportedFileExtension(let name):
                return "不支持的快捷项类型：\(name)。只支持 .app / .sh / .command / .scpt"
            case .unsupportedItem(let name):
                return "无法导入：\(name) 不是可启动的 App 或脚本"
            case .terminalLaunchFailed(let reason):
                return "启动终端脚本失败：\(reason)"
            case .itemMissing(let name):
                return "快捷项已失效：\(name)"
            case .scriptsDirectoryUnavailable:
                return "无法创建快捷项存储目录"
            }
        }
    }

    @Published private(set) var shortcuts: [ScriptShortcut] = []
    @Published private(set) var statusMessage = "拖入 .app / .sh / .command / .scpt，导入后可直接快速启动"

    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
        loadStoredShortcuts()
    }

    func importScripts(at urls: [URL]) {
        let uniqueURLs = deduplicated(urls: urls)
        guard !uniqueURLs.isEmpty else {
            statusMessage = "没有识别到可导入的快捷项"
            return
        }

        var importedNames: [String] = []
        var rejectedMessages: [String] = []

        for url in uniqueURLs {
            do {
                let shortcut = try importScript(at: url)
                importedNames.append(shortcut.displayName)
            } catch {
                rejectedMessages.append(error.localizedDescription)
            }
        }

        persistShortcuts()
        statusMessage = composeImportStatus(importedNames: importedNames, rejectedMessages: rejectedMessages)
    }

    func remove(_ shortcut: ScriptShortcut) {
        deleteStoredFile(for: shortcut)
        shortcuts.removeAll { $0.id == shortcut.id }
        persistShortcuts()
        statusMessage = "已移除快捷项：\(shortcut.displayName)"
    }

    func run(_ shortcut: ScriptShortcut) {
        do {
            let itemURL = try resolvedURL(for: shortcut)

            guard fileManager.fileExists(atPath: itemURL.path) else {
                throw StoreError.itemMissing(shortcut.displayName)
            }

            switch shortcut.kind {
            case .shell:
                try runShellScriptInTerminal(at: itemURL)
            case .appleScript:
                try runAppleScript(at: itemURL)
            case .application:
                NSWorkspace.shared.open(itemURL)
            }

            statusMessage = "已启动：\(shortcut.displayName)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func moveShortcut(id: UUID, to targetID: UUID?) -> Bool {
        guard let sourceIndex = shortcuts.firstIndex(where: { $0.id == id }) else {
            return false
        }

        var reordered = shortcuts
        let movedShortcut = reordered.remove(at: sourceIndex)

        let insertionIndex: Int
        if let targetID,
           let targetIndex = shortcuts.firstIndex(where: { $0.id == targetID }) {
            insertionIndex = targetIndex
        } else {
            insertionIndex = reordered.count
        }

        let clampedInsertionIndex = max(0, min(insertionIndex, reordered.count))
        reordered.insert(movedShortcut, at: clampedInsertionIndex)

        guard reordered != shortcuts else {
            return false
        }

        shortcuts = reordered
        persistShortcuts()
        return true
    }

    func completeReorder() {
        statusMessage = "已更新快捷启动顺序"
    }

    func reportImportFailure(_ error: Error) {
        statusMessage = "导入失败：\(error.localizedDescription)"
    }

    private func loadStoredShortcuts() {
        guard let data = defaults.data(forKey: Keys.shortcuts) else {
            return
        }

        guard let decoded = try? JSONDecoder().decode([ScriptShortcut].self, from: data) else {
            defaults.removeObject(forKey: Keys.shortcuts)
            return
        }

        let existing = decoded.filter { shortcut in
            guard let url = try? resolvedURL(for: shortcut) else {
                return false
            }

            return fileManager.fileExists(atPath: url.path)
        }

        shortcuts = existing

        if existing.count != decoded.count {
            persistShortcuts()
        }

        if !existing.isEmpty {
            statusMessage = "已保存 \(existing.count) 个快捷启动项"
        }
    }

    private func importScript(at sourceURL: URL) throws -> ScriptShortcut {
        let resolvedURL = sourceURL.standardizedFileURL
        let resourceValues = try resolvedURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        let fileName = resolvedURL.lastPathComponent
        guard let kind = ScriptShortcutKind(url: resolvedURL) else {
            throw StoreError.unsupportedFileExtension(fileName)
        }

        if kind == .application {
            guard resourceValues.isDirectory == true else {
                throw StoreError.unsupportedItem(fileName)
            }
        } else {
            guard resourceValues.isRegularFile == true else {
                throw StoreError.unsupportedItem(fileName)
            }
        }

        let fileExtension = resolvedURL.pathExtension.lowercased()

        if kind == .application {
            let shortcut = ScriptShortcut(
                id: UUID(),
                displayName: resolvedURL.deletingPathExtension().lastPathComponent,
                storedFileName: nil,
                sourcePath: resolvedURL.path,
                fileExtension: fileExtension,
                kind: kind
            )

            replaceExistingShortcutIfNeeded(with: shortcut)
            shortcuts.insert(shortcut, at: 0)
            return shortcut
        }

        let destinationDirectory = try scriptsDirectory()
        let id = UUID()
        let storedFileName = "\(id.uuidString).\(fileExtension)"
        let destinationURL = destinationDirectory.appendingPathComponent(storedFileName, isDirectory: false)

        try fileManager.copyItem(at: resolvedURL, to: destinationURL)

        if kind == .shell {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
        }

        let shortcut = ScriptShortcut(
            id: id,
            displayName: resolvedURL.deletingPathExtension().lastPathComponent,
            storedFileName: storedFileName,
            sourcePath: nil,
            fileExtension: fileExtension,
            kind: kind
        )

        replaceExistingShortcutIfNeeded(with: shortcut)
        shortcuts.insert(shortcut, at: 0)
        return shortcut
    }

    private func replaceExistingShortcutIfNeeded(with shortcut: ScriptShortcut) {
        guard let existingShortcut = shortcuts.first(where: { existing in
            existing.displayName.compare(shortcut.displayName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            return
        }

        deleteStoredFile(for: existingShortcut)
        shortcuts.removeAll { $0.id == existingShortcut.id }
    }

    private func composeImportStatus(importedNames: [String], rejectedMessages: [String]) -> String {
        switch (importedNames.isEmpty, rejectedMessages.isEmpty) {
        case (false, true):
            if importedNames.count == 1, let name = importedNames.first {
                return "已导入快捷项：\(name)"
            }

            return "已导入 \(importedNames.count) 个快捷项"
        case (false, false):
            return "已导入 \(importedNames.count) 个快捷项，忽略 \(rejectedMessages.count) 个文件"
        case (true, false):
            return rejectedMessages.first ?? "没有可导入的快捷项"
        case (true, true):
            return "没有可导入的快捷项"
        }
    }

    private func deduplicated(urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()
        var result: [URL] = []

        for url in urls {
            let path = url.standardizedFileURL.path
            if seenPaths.insert(path).inserted {
                result.append(url)
            }
        }

        return result
    }

    private func persistShortcuts() {
        guard let data = try? JSONEncoder().encode(shortcuts) else {
            return
        }

        defaults.set(data, forKey: Keys.shortcuts)
    }

    private func scriptsDirectory() throws -> URL {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StoreError.scriptsDirectoryUnavailable
        }

        let appDirectoryName = Bundle.main.bundleIdentifier ?? "NotchFlow"
        let directoryURL = baseURL
            .appendingPathComponent(appDirectoryName, isDirectory: true)
            .appendingPathComponent("Scripts", isDirectory: true)

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func storedFileURL(for shortcut: ScriptShortcut) throws -> URL {
        guard let storedFileName = shortcut.storedFileName else {
            throw StoreError.itemMissing(shortcut.displayName)
        }

        return try scriptsDirectory().appendingPathComponent(storedFileName, isDirectory: false)
    }

    private func resolvedURL(for shortcut: ScriptShortcut) throws -> URL {
        switch shortcut.kind {
        case .application:
            guard let sourcePath = shortcut.sourcePath else {
                throw StoreError.itemMissing(shortcut.displayName)
            }

            return URL(fileURLWithPath: sourcePath)
        case .shell, .appleScript:
            return try storedFileURL(for: shortcut)
        }
    }

    private func deleteStoredFile(for shortcut: ScriptShortcut) {
        guard shortcut.kind != .application else {
            return
        }

        guard let fileURL = try? storedFileURL(for: shortcut) else {
            return
        }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try? fileManager.removeItem(at: fileURL)
    }

    private func runShellScriptInTerminal(at scriptURL: URL) throws {
        let escapedDirectory = appleScriptEscaped(scriptURL.deletingLastPathComponent().path)
        let escapedPath = appleScriptEscaped(scriptURL.path)
        let source = """
        tell application \"Terminal\"
            activate
            do script \"cd \" & quoted form of \"\(escapedDirectory)\" & \"; \" & quoted form of \"\(escapedPath)\"
        end tell
        """

        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else {
            throw StoreError.terminalLaunchFailed("AppleScript 初始化失败")
        }

        appleScript.executeAndReturnError(&error)

        if let error,
           let reason = error[NSAppleScript.errorMessage] as? String {
            throw StoreError.terminalLaunchFailed(reason)
        }
    }

    private func runAppleScript(at scriptURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        try process.run()
    }

    private func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}