import Foundation

/// A snapshot of cleanup progress for the UI.
struct CleanupProgress: Equatable, Sendable {
    var fractionCompleted: Double
    var message: String
    var categoryID: FileCategory.ID?
    var itemsProcessed: Int
}

/// An item that couldn't be removed, and why.
struct CleanupFailure: Identifiable, Hashable, Sendable {
    let id = UUID()
    let itemName: String
    let reason: String
}

/// What happened to one category during cleanup.
struct CategoryCleanupOutcome: Identifiable, Sendable {
    let category: FileCategory
    let bytesRemoved: Int64
    let filesRemoved: Int
    let failures: [CleanupFailure]

    var id: FileCategory.ID { category.id }
    var movedToTrash: Bool { category.disposal == .moveToTrash }
}

/// The outcome of a whole cleanup run.
struct CleanupResult: Sendable {
    let outcomes: [CategoryCleanupOutcome]
    let duration: Duration
    /// True when the user stopped the cleanup before it finished.
    let wasStopped: Bool

    /// Space actually freed. Items moved to the Trash don't count until it's emptied.
    var bytesRecovered: Int64 {
        outcomes.filter { !$0.movedToTrash }.reduce(0) { $0 + $1.bytesRemoved }
    }

    var bytesMovedToTrash: Int64 {
        outcomes.filter(\.movedToTrash).reduce(0) { $0 + $1.bytesRemoved }
    }

    var filesRemoved: Int {
        outcomes.reduce(0) { $0 + $1.filesRemoved }
    }

    var failures: [CleanupFailure] {
        outcomes.flatMap(\.failures)
    }

    /// False when a Docker cleanup contributed objects rather than files.
    var countsOnlyFiles: Bool {
        outcomes.allSatisfy { $0.category.countsFiles || $0.filesRemoved == 0 }
    }
}
