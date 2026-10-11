import Foundation

/// Decides which direct children of a category's root folder are candidates for cleanup.
enum ItemFilter: Hashable, Sendable {
    case everything
    /// Everything except the named children (used so categories never overlap).
    case excludingNames(Set<String>)
    /// Temporary items owned by the current user that nothing has touched for a while.
    case staleTemporaryFiles(minimumAge: TimeInterval)
    /// Visible items that were added and last changed more than `days` ago.
    case olderThan(days: Int)

    private static let partialDownloadExtensions: Set<String> = [
        "download", "crdownload", "part", "partial", "opdownload",
    ]

    /// Cheap check made before an item is measured.
    func shouldMeasure(_ url: URL, now: Date) -> Bool {
        switch self {
        case .everything:
            return true

        case .excludingNames(let names):
            return !names.contains(url.lastPathComponent)

        case .staleTemporaryFiles(let minimumAge):
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let owner = attributes[.ownerAccountID] as? NSNumber,
                  owner.uint32Value == getuid(),
                  let type = attributes[.type] as? FileAttributeType,
                  type == .typeRegular || type == .typeDirectory || type == .typeSymbolicLink,
                  let modified = attributes[.modificationDate] as? Date
            else { return false }
            return now.timeIntervalSince(modified) >= minimumAge

        case .olderThan(let days):
            guard !url.lastPathComponent.hasPrefix("."),
                  !Self.partialDownloadExtensions.contains(url.pathExtension.lowercased()),
                  let reference = Self.mostRecentDate(of: url)
            else { return false }
            return reference <= Self.cutoff(days: days, now: now)
        }
    }

    /// Check made once an item's contents have been walked.
    func accepts(_ measurement: StorageAnalyzer.Measurement, now: Date) -> Bool {
        switch self {
        case .everything, .excludingNames:
            return true

        case .staleTemporaryFiles(let minimumAge):
            // Sockets and pipes mean a running process is using this item.
            guard !measurement.containsSpecialFiles else { return false }
            guard let latest = measurement.latestModificationDate else { return true }
            return now.timeIntervalSince(latest) >= minimumAge

        case .olderThan(let days):
            // A folder is only "old" if nothing inside it changed recently either.
            guard let latest = measurement.latestModificationDate else { return true }
            return latest <= Self.cutoff(days: days, now: now)
        }
    }

    private static func cutoff(days: Int, now: Date) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    /// The latest of the added, modified and created dates. Downloads often keep
    /// the server's modification date, so the date added matters most.
    private static func mostRecentDate(of url: URL) -> Date? {
        let keys: Set<URLResourceKey> = [.addedToDirectoryDateKey, .contentModificationDateKey, .creationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        return [values.addedToDirectoryDate, values.contentModificationDate, values.creationDate]
            .compactMap { $0 }
            .max()
    }
}
