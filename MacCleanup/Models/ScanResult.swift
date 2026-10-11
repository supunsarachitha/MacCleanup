import Foundation

/// One removable item found by a scan: a direct child of a category's root folder.
struct ScannedItem: Identifiable, Hashable, Sendable {
    let url: URL
    let size: Int64
    let fileCount: Int

    var id: URL { url }
}

/// A line in a category's preview list.
struct SampleEntry: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let size: Int64
    var detail: String?
}

/// Everything a read-only scan learned about one category.
struct CategoryScanResult: Identifiable, Sendable {
    enum Status: Hashable, Sendable {
        case scanned
        /// None of the category's locations exist (for example, the app isn't installed).
        case notFound
        /// macOS blocked access; Full Disk Access is needed.
        case permissionDenied
        /// The category couldn't be measured right now, with a short reason.
        case unavailable(String)
    }

    let category: FileCategory
    let status: Status
    /// Exactly what cleanup will remove, largest first. Kept out of the UI;
    /// views show `samples` instead.
    let items: [ScannedItem]
    let samples: [SampleEntry]
    let totalSize: Int64
    let fileCount: Int
    /// Items left out because a safety rule protects them.
    let protectedItemsSkipped: Int
    /// True when some, but not all, of the category's locations were blocked by macOS.
    let hasRestrictedLocations: Bool

    init(
        category: FileCategory,
        status: Status,
        items: [ScannedItem] = [],
        samples: [SampleEntry] = [],
        totalSize: Int64 = 0,
        fileCount: Int = 0,
        protectedItemsSkipped: Int = 0,
        hasRestrictedLocations: Bool = false
    ) {
        self.category = category
        self.status = status
        self.items = items
        self.samples = samples
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.protectedItemsSkipped = protectedItemsSkipped
        self.hasRestrictedLocations = hasRestrictedLocations
    }

    var id: FileCategory.ID { category.id }

    var isCleanable: Bool {
        status == .scanned && (totalSize > 0 || fileCount > 0)
    }

    /// How many removable entries aren't shown in `samples`.
    var unlistedItemCount: Int {
        max(0, items.count - samples.count)
    }
}
