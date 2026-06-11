import AppKit
import Foundation

enum ScriptShortcutKind: String, Codable {
    case shell
    case appleScript
    case application

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "sh", "command":
            self = .shell
        case "scpt":
            self = .appleScript
        case "app":
            self = .application
        default:
            return nil
        }
    }

    var label: String {
        switch self {
        case .shell:
            return "Shell"
        case .appleScript:
            return "AppleScript"
        case .application:
            return "App"
        }
    }

    var actionLabel: String {
        switch self {
        case .application:
            return "打开"
        case .shell, .appleScript:
            return "运行"
        }
    }

    var symbolName: String {
        switch self {
        case .application:
            return "square.grid.2x2"
        case .shell:
            return "terminal"
        case .appleScript:
            return "scroll"
        }
    }
}

struct ScriptShortcut: Codable, Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let storedFileName: String?
    let sourcePath: String?
    let fileExtension: String
    let kind: ScriptShortcutKind

    var detailText: String {
        kind == .application ? kind.label : "\(kind.label) · .\(fileExtension)"
    }

    var iconImage: NSImage? {
        guard kind == .application,
              let sourcePath,
              FileManager.default.fileExists(atPath: sourcePath)
        else {
            return nil
        }

        let image = NSWorkspace.shared.icon(forFile: sourcePath)
        image.size = NSSize(width: 64, height: 64)
        return image
    }
}
