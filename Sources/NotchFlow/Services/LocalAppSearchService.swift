import AppKit
import Foundation

struct LocalInstalledApp: Identifiable {
    let id: String
    let displayName: String
    let bundleIdentifier: String?
    let url: URL
    let iconImage: NSImage
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
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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

        Task { @MainActor in
            await Task.yield()
            allApps = Self.discoverApplications(fileManager: fileManager)
            isIndexing = false
            updateResults()
        }
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

    private static func discoverApplications(fileManager: FileManager) -> [LocalInstalledApp] {
        let rootURLs = applicationSearchRoots(fileManager: fileManager)
        var seenPaths = Set<String>()
        var apps: [LocalInstalledApp] = []

        for rootURL in rootURLs where fileManager.fileExists(atPath: rootURL.path) {
            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension.lowercased() == "app" else {
                    continue
                }

                let standardizedURL = fileURL.standardizedFileURL
                guard seenPaths.insert(standardizedURL.path).inserted else {
                    continue
                }

                apps.append(installedApp(at: standardizedURL))
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
        let iconImage = NSWorkspace.shared.icon(forFile: url.path)
        iconImage.size = NSSize(width: 64, height: 64)

        return LocalInstalledApp(
            id: url.path,
            displayName: displayName,
            bundleIdentifier: bundle?.bundleIdentifier,
            url: url,
            iconImage: iconImage
        )
    }

    private static func bundleDisplayName(bundle: Bundle?) -> String? {
        guard let infoDictionary = bundle?.localizedInfoDictionary ?? bundle?.infoDictionary else {
            return nil
        }

        return (infoDictionary["CFBundleDisplayName"] as? String)
            ?? (infoDictionary["CFBundleName"] as? String)
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