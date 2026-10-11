import Foundation

/// Measures how much disk space files and folders take up. Everything here is read-only.
///
/// The functions are synchronous and meant to run off the main thread. They check
/// `Task.isCancelled`, so cancelling the surrounding task stops a long walk promptly.
enum StorageAnalyzer {
    struct Measurement: Sendable {
        /// Space on disk (allocated blocks), which is what deleting actually frees.
        var size: Int64 = 0
        /// Files, links and other non-folder entries.
        var fileCount = 0
        var latestModificationDate: Date?
        /// A socket or pipe was found, which means a running process is using the item.
        var containsSpecialFiles = false
        /// Some entries couldn't be read because macOS denied access.
        var hadPermissionErrors = false
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey,
    ]

    /// Measures a file, or a folder and everything inside it. Symbolic links are
    /// counted as links and never followed.
    static func measure(_ url: URL) -> Measurement {
        var measurement = Measurement()
        let keys = Set(resourceKeys)

        guard let values = try? url.resourceValues(forKeys: keys) else {
            // The item can't even be inspected (permission problem or it vanished).
            measurement.hadPermissionErrors = true
            return measurement
        }
        record(values, into: &measurement, isRoot: true)

        guard values.isDirectory == true, values.isSymbolicLink != true else { return measurement }

        let errors = ErrorCollector()
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [],
            errorHandler: { _, error in
                errors.record(error)
                return true // keep going; one unreadable entry shouldn't stop the walk
            }
        ) else { return measurement }

        while let entry = enumerator.nextObject() as? URL {
            if Task.isCancelled { break }
            guard let entryValues = try? entry.resourceValues(forKeys: keys) else {
                measurement.hadPermissionErrors = true
                continue
            }
            record(entryValues, into: &measurement, isRoot: false)
        }

        if errors.sawPermissionError { measurement.hadPermissionErrors = true }
        return measurement
    }

    /// The direct children of a folder, including hidden ones.
    static func children(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        )
    }

    /// True when macOS refused access, typically because Full Disk Access is missing.
    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        switch nsError.domain {
        case NSCocoaErrorDomain:
            return nsError.code == NSFileReadNoPermissionError || nsError.code == NSFileWriteNoPermissionError
        case NSPOSIXErrorDomain:
            return nsError.code == Int(EPERM) || nsError.code == Int(EACCES)
        default:
            return false
        }
    }

    /// True when the error just means the item isn't there.
    static func isMissingError(_ error: Error) -> Bool {
        let nsError = error as NSError
        switch nsError.domain {
        case NSCocoaErrorDomain:
            return nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError
        case NSPOSIXErrorDomain:
            return nsError.code == Int(ENOENT)
        default:
            return false
        }
    }

    // MARK: - Private

    private static func record(_ values: URLResourceValues, into measurement: inout Measurement, isRoot: Bool) {
        let isDirectory = values.isDirectory == true && values.isSymbolicLink != true
        let isRegular = values.isRegularFile == true
        let isLink = values.isSymbolicLink == true

        if let modified = values.contentModificationDate {
            if let latest = measurement.latestModificationDate {
                measurement.latestModificationDate = max(latest, modified)
            } else {
                measurement.latestModificationDate = modified
            }
        }

        measurement.size += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)

        if isDirectory { return }
        measurement.fileCount += 1
        if !isRegular && !isLink { measurement.containsSpecialFiles = true }
    }

    /// Collects errors reported by the directory enumerator's callback.
    private final class ErrorCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var permissionError = false

        var sawPermissionError: Bool {
            lock.lock(); defer { lock.unlock() }
            return permissionError
        }

        func record(_ error: Error) {
            guard StorageAnalyzer.isPermissionError(error) else { return }
            lock.lock(); defer { lock.unlock() }
            permissionError = true
        }
    }
}
