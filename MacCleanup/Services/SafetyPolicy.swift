import Foundation

/// The last line of defence before anything is removed.
///
/// The policy is deliberately independent of the scan results: both the scan and
/// the cleanup ask it, so a bug in a category definition can't make the app touch
/// documents, media libraries or system folders.
struct SafetyPolicy: Sendable {
    enum Violation: Error, LocalizedError, Equatable {
        case protectedLocation(String)
        case outsideCategory(String)
        case tooShallow(String)

        var errorDescription: String? {
            switch self {
            case .protectedLocation(let path):
                return "\(path) is in a protected location and was left alone."
            case .outsideCategory(let path):
                return "\(path) is not inside a folder this cleanup is allowed to touch."
            case .tooShallow(let path):
                return "\(path) is too close to the top of the disk to remove safely."
            }
        }
    }

    private let protectedTrees: [String]
    private let protectedExactPaths: Set<String>

    /// Bundle-like folders that hold a user's media. Nothing inside or named
    /// like these is ever removed, wherever it sits.
    private static let protectedExtensions: Set<String> = [
        "photoslibrary", "photolibrary", "aplibrary", "musiclibrary", "tvlibrary",
        "imovielibrary", "fcpbundle", "fcpxlibrary", "logicx", "band", "sparsebundle",
    ]

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let home = homeDirectory.standardizedFileURL.path

        // Personal data and anything that holds accounts, mail or synced documents.
        let personal = [
            "Desktop", "Documents", "Pictures", "Movies", "Music", "Public", "Applications",
            "Library/Mobile Documents", "Library/CloudStorage", "Library/Photos",
            "Library/Messages", "Library/Mail", "Library/Keychains", "Library/Containers",
            "Library/Group Containers", "Library/Application Support", "Library/Preferences",
            "Library/Accounts", "Library/Calendars", "Library/Safari", "Library/Cookies",
        ].map { "\(home)/\($0)" }

        // The operating system and installed software.
        let system = [
            "/System", "/Library", "/Applications", "/usr", "/bin", "/sbin", "/etc",
            "/opt", "/cores", "/private/etc",
        ]

        protectedTrees = personal + system
        protectedExactPaths = [
            "/", home, "/Users", "/Volumes", "/private", "/private/var", "/private/tmp", "/var", "/tmp",
            "\(home)/Library", "\(home)/Downloads", "\(home)/.Trash",
            "\(home)/Library/Caches", "\(home)/Library/Logs",
        ]
    }

    /// True when the location must never be removed.
    func isProtected(_ url: URL) -> Bool {
        for path in candidatePaths(for: url) {
            if protectedExactPaths.contains(path) { return true }
            if protectedTrees.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }

            let components = (path as NSString).pathComponents
            if components.contains(where: { Self.protectedExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
                return true
            }
        }
        return false
    }

    /// Throws unless `item` is a direct child of one of `roots` and safe to remove.
    func validate(_ item: URL, within roots: [URL]) throws {
        let path = item.standardizedFileURL.path

        guard (path as NSString).pathComponents.count >= 4 else {
            throw Violation.tooShallow(path)
        }
        if isProtected(item) {
            throw Violation.protectedLocation(path)
        }

        let parent = item.deletingLastPathComponent().resolvingSymlinksInPath().path
        let isDirectChild = roots.contains { root in
            root.resolvingSymlinksInPath().path == parent
        }
        guard isDirectChild else { throw Violation.outsideCategory(path) }
    }

    /// The path as given plus its symlink-resolved form, so `/tmp/x` and
    /// `/private/tmp/x` are judged alike and a link into Documents is caught.
    private func candidatePaths(for url: URL) -> [String] {
        let plain = url.standardizedFileURL.path
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
        return plain == resolved ? [plain] : [plain, resolved]
    }
}
