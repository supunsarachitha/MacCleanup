import Foundation

/// Removes what a scan found. Only ever called after the user has confirmed.
///
/// Every item is re-checked against `SafetyPolicy` immediately before removal,
/// and items whose age rules no longer hold (for example a download that was
/// modified after the scan) are skipped rather than removed.
actor CleanupManager {
    private let safety: SafetyPolicy

    init(safety: SafetyPolicy = SafetyPolicy()) {
        self.safety = safety
    }

    /// Cleans the given scan results one category at a time. Cancelling the
    /// surrounding task stops after the item currently being removed.
    func clean(
        _ results: [CategoryScanResult],
        now: Date = Date(),
        progress: @escaping @Sendable (CleanupProgress) -> Void
    ) async -> CleanupResult {
        let clock = ContinuousClock()
        let start = clock.now

        let targets = results.filter(\.isCleanable)
        let totalWeight = max(targets.reduce(Int64(0)) { $0 + max($1.totalSize, 1) }, 1)

        var outcomes: [CategoryCleanupOutcome] = []
        var weightDone: Int64 = 0
        var itemsProcessed = 0
        var stopped = false
        var lastReport = clock.now

        func report(_ category: FileCategory, extraWeight: Int64 = 0, force: Bool = false) {
            // Thousands of tiny items would otherwise flood the UI with updates.
            guard force || clock.now - lastReport >= .milliseconds(50) else { return }
            lastReport = clock.now
            progress(CleanupProgress(
                fractionCompleted: min(Double(weightDone + extraWeight) / Double(totalWeight), 1),
                message: category.progressMessage,
                categoryID: category.id,
                itemsProcessed: itemsProcessed
            ))
        }

        for result in targets {
            if Task.isCancelled { stopped = true; break }

            let category = result.category
            report(category, force: true)

            var bytesRemoved: Int64 = 0
            var filesRemoved = 0
            var failures: [CleanupFailure] = []

            switch category.disposal {
            case .dockerPrune:
                do {
                    let pruned = try DockerService.prune()
                    bytesRemoved = pruned.bytesReclaimed
                    filesRemoved = result.fileCount
                } catch {
                    failures.append(CleanupFailure(itemName: category.name, reason: error.localizedDescription))
                }
                weightDone += max(result.totalSize, 1)

            case .deletePermanently, .moveToTrash:
                var categoryWeight: Int64 = 0
                for item in result.items {
                    if Task.isCancelled { stopped = true; break }

                    let removal = remove(item, category: category, now: now)
                    bytesRemoved += removal.bytes
                    filesRemoved += removal.files
                    if let failure = removal.failure { failures.append(failure) }

                    itemsProcessed += 1
                    categoryWeight += item.size
                    report(category, extraWeight: categoryWeight)
                }
                weightDone += max(result.totalSize, 1)
            }

            outcomes.append(CategoryCleanupOutcome(
                category: category,
                bytesRemoved: bytesRemoved,
                filesRemoved: filesRemoved,
                failures: failures
            ))
            if stopped { break }
        }

        progress(CleanupProgress(
            fractionCompleted: stopped ? min(Double(weightDone) / Double(totalWeight), 1) : 1,
            message: stopped ? "Stopped" : "Finished",
            categoryID: nil,
            itemsProcessed: itemsProcessed
        ))

        return CleanupResult(outcomes: outcomes, duration: clock.now - start, wasStopped: stopped)
    }

    // MARK: - Removing one item

    private struct Removal {
        var bytes: Int64 = 0
        var files = 0
        var failure: CleanupFailure?
    }

    private func remove(_ item: ScannedItem, category: FileCategory, now: Date) -> Removal {
        let name = item.url.lastPathComponent

        do {
            try safety.validate(item.url, within: category.roots)
        } catch {
            return Removal(failure: CleanupFailure(itemName: name, reason: error.localizedDescription))
        }

        if let reason = staleReason(for: item, category: category, now: now) {
            return Removal(failure: CleanupFailure(itemName: name, reason: reason))
        }

        let fileManager = FileManager.default
        do {
            switch category.disposal {
            case .moveToTrash:
                try fileManager.trashItem(at: item.url, resultingItemURL: nil)
            case .deletePermanently:
                try fileManager.removeItem(at: item.url)
            case .dockerPrune:
                return Removal() // handled by the caller
            }
            return Removal(bytes: item.size, files: item.fileCount)
        } catch {
            return partialRemoval(of: item, after: error)
        }
    }

    /// A failed removal can still have deleted part of a folder, so measure what
    /// is left and count only what is really gone.
    private func partialRemoval(of item: ScannedItem, after error: Error) -> Removal {
        let name = item.url.lastPathComponent
        let failure = CleanupFailure(itemName: name, reason: Self.friendlyReason(for: error))

        guard (try? FileManager.default.attributesOfItem(atPath: item.url.path)) != nil else {
            // It's gone after all (removed by something else in the meantime).
            return Removal(bytes: item.size, files: item.fileCount, failure: nil)
        }

        let remaining = StorageAnalyzer.measure(item.url)
        return Removal(
            bytes: max(0, item.size - remaining.size),
            files: max(0, item.fileCount - remaining.fileCount),
            failure: failure
        )
    }

    /// Returns a reason when the item no longer matches the rule that selected it.
    private func staleReason(for item: ScannedItem, category: FileCategory, now: Date) -> String? {
        guard case .directoryContents(_, let filter) = category.source else { return nil }

        switch filter {
        case .everything, .excludingNames:
            return nil
        case .staleTemporaryFiles, .olderThan:
            guard filter.shouldMeasure(item.url, now: now) else {
                return "Changed since the scan, so it was left alone."
            }
            let measurement = StorageAnalyzer.measure(item.url)
            guard filter.accepts(measurement, now: now) else {
                return "Changed since the scan, so it was left alone."
            }
            return nil
        }
    }

    private static func friendlyReason(for error: Error) -> String {
        if StorageAnalyzer.isPermissionError(error) {
            return "macOS didn't allow this. It may be in use, or the app may need Full Disk Access."
        }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EBUSY) {
            return "It's in use by another app."
        }
        return error.localizedDescription
    }
}
