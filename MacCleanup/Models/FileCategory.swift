import Foundation

/// A kind of reclaimable data the app knows how to find and remove.
///
/// Categories are plain data: adding a new one means adding an `ID` case and
/// describing it in `CategoryCatalog`. The scan and cleanup engines work from
/// `source` and `disposal` and need no per-category code.
struct FileCategory: Identifiable, Hashable, Sendable {
    enum ID: String, CaseIterable, Hashable, Sendable {
        case userCaches
        case logs
        case temporaryFiles
        case safariCache
        case chromeCache
        case firefoxCache
        case trash
        case xcodeDerivedData
        case xcodeArchives
        case homebrewDownloads
        case docker
        case oldDownloads
    }

    /// Where a category's data comes from.
    enum Source: Hashable, Sendable {
        /// The direct children of each root folder that pass `filter`.
        /// The roots themselves are never removed.
        case directoryContents(roots: [URL], filter: ItemFilter)
        /// Space the Docker CLI reports as reclaimable.
        case docker
    }

    /// What "cleaning" means for a category.
    enum Disposal: Hashable, Sendable {
        case deletePermanently
        /// Used for the user's own files, so a mistake stays recoverable.
        case moveToTrash
        case dockerPrune
    }

    let id: ID
    let name: String
    let symbolName: String
    /// One line explaining what this data is and why removing it is safe.
    let summary: String
    /// Shown when removing this category deserves a second thought.
    let warning: String?
    /// Status line shown while this category is being cleaned.
    let progressMessage: String
    let source: Source
    let disposal: Disposal
    let isSelectedByDefault: Bool

    /// The folders this category looks in. Empty for non-file sources.
    var roots: [URL] {
        if case .directoryContents(let roots, _) = source { return roots }
        return []
    }

    /// False when the category counts something other than files (Docker objects).
    var countsFiles: Bool { disposal != .dockerPrune }
}
