import AppKit
import Foundation

struct LocalInstalledApp: Identifiable, Sendable {
    let id: String
    let displayName: String
    let bundleIdentifier: String?
    let url: URL

    @MainActor
    var iconImage: NSImage {
        let cacheKey = url as NSURL
        if let cachedImage = Self.iconCache.object(forKey: cacheKey) {
            return cachedImage
        }

        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 64, height: 64)
        Self.iconCache.setObject(image, forKey: cacheKey)
        return image
    }

    @MainActor
    private static let iconCache = NSCache<NSURL, NSImage>()
}

protocol LocalApplicationScanning: Sendable {
    func discoverApplications() -> [LocalInstalledApp]
}

@MainActor
final class LocalAppSearchService: ObservableObject {
    @Published var query = "" {
        didSet {
            updateResults()
        }
    }

    @Published private(set) var results: [LocalInstalledApp] = []
    @Published private(set) var isIndexing = false

    private var hasStarted = false
    private var allApps: [LocalInstalledApp] = []
    private let scanner: any LocalApplicationScanning
    private var indexingTask: Task<Void, Never>?

    init(
        fileManager: FileManager = .default,
        scanner: (any LocalApplicationScanning)? = nil
    ) {
        self.scanner = scanner ?? FileSystemLocalApplicationScanner(fileManager: fileManager)
    }

    var visibleResults: [LocalInstalledApp] {
        Array(results.prefix(6))
    }

    func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        isIndexing = true

        indexingTask = Task.detached(priority: .utility) { [weak self, scanner] in
            let discoveredApps = scanner.discoverApplications()
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                guard let self, !Task.isCancelled else {
                    return
                }

                self.allApps = discoveredApps
                self.isIndexing = false
                self.indexingTask = nil
                self.updateResults()
            }
        }
    }

    func stop() {
        indexingTask?.cancel()
        indexingTask = nil
        hasStarted = false
        isIndexing = false
    }

    func clearQuery() {
        query = ""
    }

    func activateTopResult() {
        guard let app = visibleResults.first else {
            return
        }

        open(app)
    }

    func open(_ app: LocalInstalledApp) {
        NSWorkspace.shared.open(app.url)
        clearQuery()
    }

    private func updateResults() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            return
        }

        let normalizedQuery = Self.normalized(trimmedQuery)
        results = allApps
            .compactMap { app -> (LocalInstalledApp, Int)? in
                guard let score = Self.matchScore(for: app, query: normalizedQuery) else {
                    return nil
                }

                return (app, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 < rhs.1
                }

                return lhs.0.displayName.localizedCaseInsensitiveCompare(rhs.0.displayName) == .orderedAscending
            }
            .map(\.0)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    private static func matchScore(for app: LocalInstalledApp, query: String) -> Int? {
        let displayName = normalized(app.displayName)
        let bundleIdentifier = app.bundleIdentifier.map(normalized) ?? ""
        let path = normalized(app.url.path)

        if displayName == query {
            return 0
        }

        if displayName.hasPrefix(query) {
            return 10 + displayName.count
        }

        if displayName.split(separator: " ").contains(where: { $0.hasPrefix(query) }) {
            return 24 + displayName.count
        }

        if let range = displayName.range(of: query) {
            return 40 + displayName.distance(from: displayName.startIndex, to: range.lowerBound)
        }

        if let range = bundleIdentifier.range(of: query) {
            return 70 + bundleIdentifier.distance(from: bundleIdentifier.startIndex, to: range.lowerBound)
        }

        if let range = path.range(of: query) {
            return 90 + path.distance(from: path.startIndex, to: range.lowerBound)
        }

        return nil
    }
}

private final class FileSystemLocalApplicationScanner: LocalApplicationScanning, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func discoverApplications() -> [LocalInstalledApp] {
        let rootURLs = Self.applicationSearchRoots(fileManager: fileManager)
        var seenPaths = Set<String>()
        var apps: [LocalInstalledApp] = []

        for rootURL in rootURLs where fileManager.fileExists(atPath: rootURL.path) {
            guard !Task.isCancelled else {
                return []
            }

            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard !Task.isCancelled else {
                    return []
                }

                guard fileURL.pathExtension.lowercased() == "app" else {
                    continue
                }

                let standardizedURL = fileURL.standardizedFileURL
                guard seenPaths.insert(standardizedURL.path).inserted else {
                    continue
                }

                apps.append(Self.installedApp(at: standardizedURL))
            }
        }

        return apps.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func applicationSearchRoots(fileManager: FileManager) -> [URL] {
        var roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
        ]

        if let userApplicationsURL = fileManager.urls(for: .applicationDirectory, in: .userDomainMask).first {
            roots.append(userApplicationsURL)
        }

        return roots
    }

    private static func installedApp(at url: URL) -> LocalInstalledApp {
        let bundle = Bundle(url: url)
        let displayName = bundleDisplayName(bundle: bundle)
            ?? url.deletingPathExtension().lastPathComponent

        return LocalInstalledApp(
            id: url.path,
            displayName: displayName,
            bundleIdentifier: bundle?.bundleIdentifier,
            url: url
        )
    }

    private static func bundleDisplayName(bundle: Bundle?) -> String? {
        guard let infoDictionary = bundle?.localizedInfoDictionary ?? bundle?.infoDictionary else {
            return nil
        }

        return (infoDictionary["CFBundleDisplayName"] as? String)
            ?? (infoDictionary["CFBundleName"] as? String)
    }
}
