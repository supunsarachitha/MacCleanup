import Foundation

/// User-adjustable inputs to a scan.
struct ScanConfiguration: Sendable {
    var downloadsAgeDays: Int = Preferences.defaultDownloadsAgeDays
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
}

enum Preferences {
    static let downloadsAgeKey = "downloadsAgeDays"
    static let defaultDownloadsAgeDays = 30
    static let downloadsAgeRange = 7...365

    static var downloadsAgeDays: Int {
        let stored = UserDefaults.standard.integer(forKey: downloadsAgeKey)
        guard stored != 0 else { return defaultDownloadsAgeDays }
        return min(max(stored, downloadsAgeRange.lowerBound), downloadsAgeRange.upperBound)
    }
}

/// The list of places the app knows how to clean. To support a new kind of
/// clutter, add an `ID` case and one entry here.
enum CategoryCatalog {
    /// Temporary files younger than this may still be in use. macOS itself
    /// clears /tmp items that haven't been touched for three days.
    private static let temporaryFileMinimumAge: TimeInterval = 3 * 86_400

    static func categories(configuration: ScanConfiguration = ScanConfiguration()) -> [FileCategory] {
        let home = configuration.homeDirectory
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        let xcode = library.appendingPathComponent("Developer/Xcode", isDirectory: true)
        let days = configuration.downloadsAgeDays

        return [
            FileCategory(
                id: .userCaches,
                name: "User Cache",
                symbolName: "square.stack.3d.up",
                summary: "Temporary data apps keep to run faster. They rebuild it when needed.",
                warning: "Apps may take a little longer to open the first time afterwards.",
                progressMessage: "Deleting caches…",
                // Browser and Homebrew caches have their own categories below.
                source: .directoryContents(
                    roots: [caches],
                    filter: .excludingNames(["com.apple.Safari", "Google", "Firefox", "Homebrew"])
                ),
                disposal: .deletePermanently,
                isSelectedByDefault: true
            ),
            FileCategory(
                id: .logs,
                name: "Logs",
                symbolName: "doc.text",
                summary: "Diagnostic logs written by apps and macOS.",
                warning: nil,
                progressMessage: "Deleting logs…",
                source: .directoryContents(
                    roots: [library.appendingPathComponent("Logs", isDirectory: true)],
                    filter: .everything
                ),
                disposal: .deletePermanently,
                isSelectedByDefault: true
            ),
            FileCategory(
                id: .temporaryFiles,
                name: "Temporary Files",
                symbolName: "clock.arrow.circlepath",
                summary: "Your own files in /tmp and /private/var/tmp that haven't been touched for 3 days.",
                warning: nil,
                progressMessage: "Deleting temporary files…",
                source: .directoryContents(
                    roots: [
                        URL(fileURLWithPath: "/private/tmp", isDirectory: true),
                        URL(fileURLWithPath: "/private/var/tmp", isDirectory: true),
                    ],
                    filter: .staleTemporaryFiles(minimumAge: temporaryFileMinimumAge)
                ),
                disposal: .deletePermanently,
                isSelectedByDefault: true
            ),
            FileCategory(
                id: .safariCache,
                name: "Safari Cache",
                symbolName: "safari",
                summary: "Web pages and images Safari saved to load sites faster.",
                warning: "Quit Safari first. Needs Full Disk Access to be scanned.",
                progressMessage: "Deleting Safari cache…",
                source: .directoryContents(
                    roots: [caches.appendingPathComponent("com.apple.Safari", isDirectory: true)],
                    filter: .everything
                ),
                disposal: .deletePermanently,
                isSelectedByDefault: true
            ),
            FileCategory(
                id: .chromeCache,
                name: "Chrome Cache",
                symbolName: "globe",
                summary: "Web pages and images Google Chrome saved to load sites faster.",
                warning: "Quit Chrome first for the best result.",
                progressMessage: "Deleting Chrome cache…",
                source: .directoryContents(
                    roots: [caches.appendingPathComponent("Google/Chrome", isDirectory: true)],
                    filter: .everything
                ),
                disposal: .deletePermanently,
                isSelectedByDefault: true
            ),
            FileCategory(
                id: .firefoxCache,
                name: "Firefox Cache",
                symbolName: "flame",
                summary: "Web pages and images Firefox saved to load sites faster.",
                warning: "Quit Firefox first for the best result.",
                progressMessage: "Deleting Firefox cache…",
                source: .directoryContents(
                    roots: [caches.appendingPathComponent("Firefox/Profiles", isDirectory: true)],
                    filter: .everything
                ),
                disposal: .deletePermanently,
                isSelectedByDefault: true
            ),
            FileCategory(
                id: .trash,
                name: "Trash",
                symbolName: "trash",
                summary: "Items you already moved to the Trash.",
                warning: "Emptying the Trash permanently removes everything in it. Needs Full Disk Access to be scanned.",
                progressMessage: "Emptying Trash…",
                source: .directoryContents(
                    roots: [home.appendingPathComponent(".Trash", isDirectory: true)],
                    filter: .everything
                ),
                disposal: .deletePermanently,
                isSelectedByDefault: true
            ),
            FileCategory(
                id: .xcodeDerivedData,
                name: "Xcode Derived Data",
                symbolName: "hammer",
                summary: "Build products and indexes. Xcode regenerates them the next time you build.",
                warning: "The next build of each project will be slower.",
                progressMessage: "Cleaning Xcode data…",
                source: .directoryContents(
                    roots: [xcode.appendingPathComponent("DerivedData", isDirectory: true)],
                    filter: .everything
                ),
                disposal: .deletePermanently,
                isSelectedByDefault: true
            ),
            FileCategory(
                id: .xcodeArchives,
                name: "Xcode Archives",
                symbolName: "archivebox",
                summary: "App archives made with Product ▸ Archive.",
                warning: "Archives are needed to re-submit builds and to symbolicate crash reports. They are moved to the Trash, not deleted.",
                progressMessage: "Moving Xcode archives to the Trash…",
                source: .directoryContents(
                    roots: [xcode.appendingPathComponent("Archives", isDirectory: true)],
                    filter: .everything
                ),
                disposal: .moveToTrash,
                isSelectedByDefault: false
            ),
            FileCategory(
                id: .homebrewDownloads,
                name: "Homebrew Downloads",
                symbolName: "cup.and.saucer",
                summary: "Installers Homebrew downloaded earlier. They are fetched again if needed.",
                warning: nil,
                progressMessage: "Deleting Homebrew downloads…",
                source: .directoryContents(
                    roots: [
                        caches.appendingPathComponent("Homebrew/downloads", isDirectory: true),
                        caches.appendingPathComponent("Homebrew/Cask", isDirectory: true),
                    ],
                    filter: .everything
                ),
                disposal: .deletePermanently,
                isSelectedByDefault: true
            ),
            FileCategory(
                id: .docker,
                name: "Docker",
                symbolName: "shippingbox",
                summary: "Stopped containers, dangling images and unused build cache. Volumes are never touched.",
                warning: "Sizes are estimates reported by Docker.",
                progressMessage: "Pruning Docker resources…",
                source: .docker,
                disposal: .dockerPrune,
                isSelectedByDefault: true
            ),
            FileCategory(
                id: .oldDownloads,
                name: "Downloads > \(days) Days",
                symbolName: "arrow.down.circle",
                summary: "Items in Downloads you haven't added or changed in over \(days) days.",
                warning: "These are your own files. They are moved to the Trash so you can still recover them.",
                progressMessage: "Moving old downloads to the Trash…",
                source: .directoryContents(
                    roots: [home.appendingPathComponent("Downloads", isDirectory: true)],
                    filter: .olderThan(days: days)
                ),
                disposal: .moveToTrash,
                isSelectedByDefault: false
            ),
        ]
    }
}

extension FileCategory {
    /// Human-readable locations, with the home folder shortened to `~`.
    var locationDescriptions: [String] {
        if case .docker = source { return ["Docker Engine (via the docker command)"] }
        return roots.map { ($0.path as NSString).abbreviatingWithTildeInPath }
    }
}
