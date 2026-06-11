import AppKit
import Combine
import Foundation

struct ClipboardHistoryEntry: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let capturedAt: Date

    init(id: UUID = UUID(), text: String, capturedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.capturedAt = capturedAt
    }

    var previewText: String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsed.isEmpty else {
            return "空白文本"
        }

        return collapsed
    }

    var detailText: String {
        let lineCount = text
            .split(whereSeparator: \.isNewline)
            .count

        if lineCount > 1 {
            return "\(lineCount) 行文本"
        }

        return "\(text.count) 个字符"
    }
}

@MainActor
final class ClipboardHistoryService: ObservableObject {
    @Published private(set) var entries: [ClipboardHistoryEntry] = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var statusMessage = "等待复制文本"

    private let settings: AppSettings
    private let pasteboard: NSPasteboard
    private let pollingInterval: TimeInterval = 0.7
    private let maximumEntries = 12
    private let maximumStoredTextLength = 4_000
    private let persistenceURL: URL?

    private var pollTimer: Timer?
    private var lastChangeCount: Int
    private var hasStarted = false
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings, pasteboard: NSPasteboard = .general) {
        self.settings = settings
        self.pasteboard = pasteboard
        persistenceURL = Self.makePersistenceURL()
        lastChangeCount = pasteboard.changeCount
        entries = Self.loadPersistedEntries(from: persistenceURL, maximumEntries: maximumEntries)
    }

    func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        bindSettings()

        if settings.clipboardHistoryEnabled {
            startMonitoring()
            captureCurrentPasteboardIfNeeded(force: true)
        } else {
            statusMessage = "剪贴板历史已关闭"
        }
    }

    func stop() {
        stopMonitoring()
        cancellables.removeAll()
        hasStarted = false
    }

    func clearHistory() {
        entries = []
        statusMessage = settings.clipboardHistoryEnabled ? "历史已清空" : "剪贴板历史已关闭"
        persistEntries()
    }

    func copy(_ entry: ClipboardHistoryEntry) {
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        lastChangeCount = pasteboard.changeCount

        recordText(entry.text, preferredID: entry.id)
        statusMessage = "已复制回剪贴板"
    }

    private func bindSettings() {
        guard cancellables.isEmpty else {
            return
        }

        settings.$clipboardHistoryEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard let self else {
                    return
                }

                if isEnabled {
                    self.startMonitoring()
                    self.captureCurrentPasteboardIfNeeded(force: true)
                    if self.entries.isEmpty {
                        self.statusMessage = "等待复制文本"
                    } else {
                        self.statusMessage = "已恢复 \(self.entries.count) 条文本"
                    }
                } else {
                    self.stopMonitoring()
                    self.statusMessage = "剪贴板历史已关闭"
                }
            }
            .store(in: &cancellables)
    }

    private func startMonitoring() {
        guard pollTimer == nil else {
            return
        }

        isMonitoring = true
        lastChangeCount = pasteboard.changeCount

        let timer = Timer(timeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureCurrentPasteboardIfNeeded()
            }
        }

        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        isMonitoring = false
    }

    private func captureCurrentPasteboardIfNeeded(force: Bool = false) {
        guard settings.clipboardHistoryEnabled else {
            return
        }

        let changeCount = pasteboard.changeCount
        guard force || changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = changeCount

        guard let rawText = pasteboard.string(forType: .string) else {
            if entries.isEmpty {
                statusMessage = "等待复制纯文本"
            } else {
                statusMessage = "最近一次复制不是纯文本"
            }
            return
        }

        let sanitizedText = sanitized(rawText)
        guard !sanitizedText.isEmpty else {
            statusMessage = entries.isEmpty ? "等待复制纯文本" : "已忽略空白文本"
            return
        }

        recordText(sanitizedText)
        statusMessage = "已记录 \(entries.count) 条文本"
    }

    private func recordText(_ text: String, preferredID: UUID? = nil) {
        if let existingIndex = entries.firstIndex(where: { $0.text == text }) {
            let existing = entries.remove(at: existingIndex)
            entries.insert(
                ClipboardHistoryEntry(
                    id: preferredID ?? existing.id,
                    text: text,
                    capturedAt: Date()
                ),
                at: 0
            )
            persistEntries()
            return
        }

        entries.insert(
            ClipboardHistoryEntry(
                id: preferredID ?? UUID(),
                text: text,
                capturedAt: Date()
            ),
            at: 0
        )

        if entries.count > maximumEntries {
            entries.removeLast(entries.count - maximumEntries)
        }

        persistEntries()
    }

    private func sanitized(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        guard trimmed.count > maximumStoredTextLength else {
            return trimmed
        }

        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maximumStoredTextLength)
        return String(trimmed[..<endIndex])
    }

    private func persistEntries() {
        guard let persistenceURL else {
            return
        }

        if entries.isEmpty {
            try? FileManager.default.removeItem(at: persistenceURL)
            return
        }

        let encoder = JSONEncoder()

        do {
            let data = try encoder.encode(entries)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            assertionFailure("Failed to persist clipboard history: \(error)")
        }
    }

    private static func loadPersistedEntries(from url: URL?, maximumEntries: Int) -> [ClipboardHistoryEntry] {
        guard let url else {
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([ClipboardHistoryEntry].self, from: data)
            return Array(decoded.prefix(maximumEntries))
        } catch {
            return []
        }
    }

    private static func makePersistenceURL() -> URL? {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let folderURL = applicationSupportURL
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "NotchFlow", isDirectory: true)
            .appendingPathComponent("ClipboardHistory", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            return folderURL.appendingPathComponent("entries.json")
        } catch {
            return nil
        }
    }
}
