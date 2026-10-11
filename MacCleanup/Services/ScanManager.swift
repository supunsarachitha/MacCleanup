import Foundation

struct ScanProgress: Equatable, Sendable {
    var fractionCompleted: Double
    var message: String
}

/// Finds what could be cleaned. This type only reads: it has no code path that
/// modifies or removes anything.
actor ScanManager {
    /// How many entries a category's preview lists.
    static let sampleLimit = 5

    private let safety: SafetyPolicy

    init(safety: SafetyPolicy = SafetyPolicy()) {
        self.safety = safety
    }

    /// Scans every category concurrently and returns results in the order given.
    func scan(
        categories: [FileCategory],
        now: Date = Date(),
        progress: @escaping @Sendable (ScanProgress) -> Void
    ) async -> [CategoryScanResult] {
        progress(ScanProgress(fractionCompleted: 0, message: "Starting scan…"))

        let safety = self.safety
        let total = max(categories.count, 1)
        var resultsByID: [FileCategory.ID: CategoryScanResult] = [:]

        await withTaskGroup(of: CategoryScanResult.self) { group in
            for category in categories {
                group.addTask { Self.scan(category, safety: safety, now: now) }
            }

            var completed = 0
            for await result in group {
                completed += 1
                resultsByID[result.id] = result
                progress(ScanProgress(
                    fractionCompleted: Double(completed) / Double(total),
                    message: "Checked \(result.category.name)"
                ))
            }
        }

        return categories.compactMap { resultsByID[$0.id] }
    }

    // MARK: - Per-category scanning

    private static func scan(_ category: FileCategory, safety: SafetyPolicy, now: Date) -> CategoryScanResult {
        switch category.source {
        case .directoryContents(let roots, let filter):
            return scanDirectories(category, roots: roots, filter: filter, safety: safety, now: now)
        case .docker:
            return scanDocker(category)
        }
    }

    private static func scanDirectories(
        _ category: FileCategory,
        roots: [URL],
        filter: ItemFilter,
        safety: SafetyPolicy,
        now: Date
    ) -> CategoryScanResult {
        var items: [ScannedItem] = []
        var existingRoots = 0
        var deniedRoots = 0
        var protectedSkipped = 0
        var sawRestrictedContent = false

        for root in roots {
            if Task.isCancelled { break }

            let children: [URL]
            do {
                children = try StorageAnalyzer.children(of: root)
            } catch {
                if StorageAnalyzer.isMissingError(error) { continue }
                existingRoots += 1
                if StorageAnalyzer.isPermissionError(error) { deniedRoots += 1 }
                continue
            }
            existingRoots += 1

            for child in children {
                if Task.isCancelled { break }
                guard filter.shouldMeasure(child, now: now) else { continue }

                // Items the safety policy protects are never offered for cleanup.
                do {
                    try safety.validate(child, within: roots)
                } catch {
                    protectedSkipped += 1
                    continue
                }

                let measurement = StorageAnalyzer.measure(child)
                if measurement.hadPermissionErrors { sawRestrictedContent = true }
                guard filter.accepts(measurement, now: now) else { continue }

                items.append(ScannedItem(url: child, size: measurement.size, fileCount: measurement.fileCount))
            }
        }

        if existingRoots == 0 {
            return CategoryScanResult(category: category, status: .notFound)
        }
        if deniedRoots == existingRoots {
            return CategoryScanResult(category: category, status: .permissionDenied)
        }

        items.sort { $0.size > $1.size }

        let samples = items.prefix(sampleLimit).enumerated().map { index, item in
            SampleEntry(
                id: index,
                name: item.url.lastPathComponent,
                size: item.size,
                detail: item.fileCount > 1 ? "\(item.fileCount.formatted()) files" : nil
            )
        }

        return CategoryScanResult(
            category: category,
            status: .scanned,
            items: items,
            samples: Array(samples),
            totalSize: items.reduce(0) { $0 + $1.size },
            fileCount: items.reduce(0) { $0 + $1.fileCount },
            protectedItemsSkipped: protectedSkipped,
            hasRestrictedLocations: deniedRoots > 0 || sawRestrictedContent
        )
    }

    private static func scanDocker(_ category: FileCategory) -> CategoryScanResult {
        do {
            let estimate = try DockerService.estimate()
            let samples = estimate.parts.enumerated().map { index, part in
                SampleEntry(
                    id: index,
                    name: part.name,
                    size: part.bytes,
                    detail: part.objectCount > 0 ? "\(part.objectCount.formatted()) objects" : nil
                )
            }
            return CategoryScanResult(
                category: category,
                status: .scanned,
                samples: samples,
                totalSize: estimate.totalBytes,
                fileCount: estimate.objectCount
            )
        } catch DockerService.DockerError.notInstalled {
            return CategoryScanResult(category: category, status: .notFound)
        } catch {
            return CategoryScanResult(
                category: category,
                status: .unavailable(error.localizedDescription)
            )
        }
    }
}
