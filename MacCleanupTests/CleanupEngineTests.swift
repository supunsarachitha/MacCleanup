import XCTest
@testable import MacCleanup

final class CleanupEngineTests: XCTestCase {
    private var sandbox: URL!
    private var cacheRoot: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleanupTests-\(UUID().uuidString)", isDirectory: true)
        cacheRoot = sandbox.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    // MARK: Helpers

    private func write(_ bytes: Int, to relativePath: String, in root: URL? = nil) throws -> URL {
        let url = (root ?? cacheRoot).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
        return url
    }

    private func category(
        root: URL? = nil,
        disposal: FileCategory.Disposal = .deletePermanently,
        filter: ItemFilter = .everything
    ) -> FileCategory {
        FileCategory(
            id: .userCaches,
            name: "Test",
            symbolName: "doc",
            summary: "",
            warning: nil,
            progressMessage: "Working…",
            source: .directoryContents(roots: [root ?? cacheRoot], filter: filter),
            disposal: disposal,
            isSelectedByDefault: true
        )
    }

    // MARK: Scan

    func testScanReportsSizeAndFileCountWithoutDeletingAnything() async throws {
        let first = try write(20_000, to: "AppA/data.bin")
        let second = try write(20_000, to: "AppA/more.bin")
        let third = try write(8_000, to: "AppB.cache")

        let results = await ScanManager().scan(categories: [category()]) { _ in }

        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.status, .scanned)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.fileCount, 3)
        XCTAssertGreaterThanOrEqual(result.totalSize, 48_000)
        XCTAssertEqual(result.items.first?.url.lastPathComponent, "AppA", "Largest item comes first")

        for url in [first, second, third] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Scanning must never delete")
        }
    }

    func testScanLimitsPreviewSamples() async throws {
        for index in 0..<12 {
            _ = try write(1_000, to: "Item\(index)/file.bin")
        }

        let results = await ScanManager().scan(categories: [category()]) { _ in }

        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.items.count, 12)
        XCTAssertEqual(result.samples.count, ScanManager.sampleLimit)
        XCTAssertEqual(result.unlistedItemCount, 12 - ScanManager.sampleLimit)
    }

    func testMissingLocationIsReportedAsNotFound() async {
        let missing = sandbox.appendingPathComponent("DoesNotExist", isDirectory: true)

        let results = await ScanManager().scan(categories: [category(root: missing)]) { _ in }

        XCTAssertEqual(results.first?.status, .notFound)
    }

    func testRecentDownloadsAreNotOffered() async throws {
        let downloads = sandbox.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        _ = try write(5_000, to: "fresh.zip", in: downloads)

        let results = await ScanManager().scan(
            categories: [category(root: downloads, disposal: .moveToTrash, filter: .olderThan(days: 30))]
        ) { _ in }

        XCTAssertEqual(results.first?.items.count, 0)
        XCTAssertEqual(results.first?.isCleanable, false)
    }

    // MARK: Cleanup

    func testCleanupRemovesItemsButKeepsTheRootFolder() async throws {
        let file = try write(10_000, to: "AppA/data.bin")
        let single = try write(4_000, to: "AppB.cache")

        let cat = category()
        let scan = await ScanManager().scan(categories: [cat]) { _ in }
        let result = await CleanupManager().clean(scan) { _ in }

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: single.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheRoot.path), "The category's own folder must stay")
        XCTAssertEqual(result.filesRemoved, 2)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(result.wasStopped)
        XCTAssertGreaterThan(result.bytesRecovered, 0)
    }

    func testCleanupOnlyTouchesWhatTheScanFound() async throws {
        _ = try write(10_000, to: "Found/data.bin")
        let scan = await ScanManager().scan(categories: [category()]) { _ in }

        // Appears after the scan, so the user never saw it.
        let late = try write(10_000, to: "Late/data.bin")

        _ = await CleanupManager().clean(scan) { _ in }

        XCTAssertTrue(FileManager.default.fileExists(atPath: late.path))
    }

    func testCleanupRefusesItemsOutsideTheCategory() async throws {
        let outside = try write(5_000, to: "important.txt", in: sandbox)
        let forged = CategoryScanResult(
            category: category(),
            status: .scanned,
            items: [ScannedItem(url: outside, size: 5_000, fileCount: 1)],
            totalSize: 5_000,
            fileCount: 1
        )

        let result = await CleanupManager().clean([forged]) { _ in }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.filesRemoved, 0)
    }

    func testCleanupReportsProgressUpToOne() async throws {
        for index in 0..<5 {
            _ = try write(2_000, to: "Item\(index)/file.bin")
        }
        let scan = await ScanManager().scan(categories: [category()]) { _ in }
        let recorder = ProgressRecorder()

        _ = await CleanupManager().clean(scan) { recorder.record($0) }

        XCTAssertEqual(recorder.last?.fractionCompleted, 1)
        XCTAssertEqual(recorder.last?.message, "Finished")
    }

    // MARK: Safety policy

    func testSafetyPolicyProtectsPersonalFoldersAndLibraries() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let policy = SafetyPolicy(homeDirectory: home)

        let protectedPaths = [
            home,
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents/Taxes/2025.pdf"),
            home.appendingPathComponent("Pictures/Photos Library.photoslibrary"),
            home.appendingPathComponent("Music/Music/Music Library.musiclibrary"),
            home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"),
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/System/Library"),
            URL(fileURLWithPath: "/Applications/Safari.app"),
        ]
        for url in protectedPaths {
            XCTAssertTrue(policy.isProtected(url), "\(url.path) should be protected")
        }
    }

    func testSafetyPolicyAllowsCacheItems() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let policy = SafetyPolicy(homeDirectory: home)
        let caches = home.appendingPathComponent("Library/Caches")
        let item = caches.appendingPathComponent("com.example.app")

        XCTAssertNoThrow(try policy.validate(item, within: [caches]))
    }

    func testSafetyPolicyRejectsNestedAndForeignItems() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let policy = SafetyPolicy(homeDirectory: home)
        let caches = home.appendingPathComponent("Library/Caches")

        let nested = caches.appendingPathComponent("com.example.app/inner")
        XCTAssertThrowsError(try policy.validate(nested, within: [caches]))

        let foreign = home.appendingPathComponent("Library/Other/thing")
        XCTAssertThrowsError(try policy.validate(foreign, within: [caches]))
    }

    func testCatalogNeverTargetsProtectedLocations() {
        let policy = SafetyPolicy()
        for category in CategoryCatalog.categories() {
            for root in category.roots {
                XCTAssertFalse(
                    policy.isProtected(root.appendingPathComponent("anything")),
                    "\(category.name) points at a protected location: \(root.path)"
                )
            }
        }
    }

    func testCatalogHasNoDuplicateIDs() {
        let ids = CategoryCatalog.categories().map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(ids), Set(FileCategory.ID.allCases))
    }

    // MARK: Docker parsing

    func testDockerSizeParsing() {
        XCTAssertEqual(DockerService.parseSize("0B"), 0)
        XCTAssertEqual(DockerService.parseSize("45.3kB"), 45_300)
        XCTAssertEqual(DockerService.parseSize("512MB"), 512_000_000)
        XCTAssertEqual(DockerService.parseSize("1.2 GB"), 1_200_000_000)
        XCTAssertEqual(DockerService.parseSize("3.2GB (45%)"), 3_200_000_000)
        XCTAssertNil(DockerService.parseSize("lots"))
    }

    func testDockerReclaimedSpaceParsing() {
        let output = """
        Deleted Containers:
        abc123

        Total reclaimed space: 1.5GB
        """
        XCTAssertEqual(DockerService.reclaimedBytes(in: output), 1_500_000_000)
        XCTAssertNil(DockerService.reclaimedBytes(in: "nothing here"))
    }

    // MARK: Formatting

    func testByteFormatSplitsValueAndUnit() {
        let parts = ByteFormat.parts(47_000_000_000)
        XCTAssertEqual(parts.unit, "GB")
        XCTAssertTrue(parts.value.hasPrefix("47"))
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CleanupProgress] = []

    var last: CleanupProgress? {
        lock.lock(); defer { lock.unlock() }
        return values.last
    }

    func record(_ progress: CleanupProgress) {
        lock.lock(); defer { lock.unlock() }
        values.append(progress)
    }
}
