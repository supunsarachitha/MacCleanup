import Foundation
import Observation

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview
    case review
    case safety

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .review: return "Review Details"
        case .safety: return "Safety"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .review: return "list.bullet.rectangle"
        case .safety: return "checkmark.shield"
        }
    }
}

/// Drives the whole app: scan → review → select → confirm → clean → results.
@MainActor
@Observable
final class CleanupViewModel {
    enum Phase: Equatable {
        case idle
        case scanning(ScanProgress)
        case ready
        case cleaning(CleanupProgress)
        case finished

        var isBusy: Bool {
            switch self {
            case .scanning, .cleaning: return true
            case .idle, .ready, .finished: return false
            }
        }
    }

    // MARK: State

    private(set) var phase: Phase = .idle
    private(set) var scanResults: [CategoryScanResult] = []
    private(set) var lastResult: CleanupResult?
    private(set) var selectedIDs: Set<FileCategory.ID> = []

    var selection: SidebarItem = .overview
    var isConfirmingCleanup = false

    @ObservationIgnored private let scanManager: ScanManager
    @ObservationIgnored private let cleanupManager: CleanupManager
    @ObservationIgnored private var activeTask: Task<Void, Never>?

    init(scanManager: ScanManager = ScanManager(), cleanupManager: CleanupManager = CleanupManager()) {
        self.scanManager = scanManager
        self.cleanupManager = cleanupManager
    }

    // MARK: Derived values

    /// Categories that have something to clean.
    var cleanableResults: [CategoryScanResult] {
        scanResults.filter(\.isCleanable)
    }

    /// Categories with nothing to clean, with the reason.
    var otherResults: [CategoryScanResult] {
        scanResults.filter { !$0.isCleanable }
    }

    var selectedResults: [CategoryScanResult] {
        cleanableResults.filter { selectedIDs.contains($0.id) }
    }

    var totalFoundBytes: Int64 {
        cleanableResults.reduce(0) { $0 + $1.totalSize }
    }

    var selectedBytes: Int64 {
        selectedResults.reduce(0) { $0 + $1.totalSize }
    }

    var selectedFileCount: Int {
        selectedResults.filter { $0.category.countsFiles }.reduce(0) { $0 + $1.fileCount }
    }

    var selectedDockerObjectCount: Int {
        selectedResults.filter { !$0.category.countsFiles }.reduce(0) { $0 + $1.fileCount }
    }

    var canClean: Bool {
        phase == .ready && !selectedResults.isEmpty
    }

    var hasRestrictedLocations: Bool {
        scanResults.contains { $0.status == .permissionDenied || $0.hasRestrictedLocations }
    }

    var hasScanResults: Bool {
        phase == .ready || phase == .finished || !scanResults.isEmpty
    }

    /// True when at least one selected category is removed permanently.
    var selectionIncludesPermanentDeletion: Bool {
        selectedResults.contains { $0.category.disposal != .moveToTrash }
    }

    var selectionIncludesTrashMoves: Bool {
        selectedResults.contains { $0.category.disposal == .moveToTrash }
    }

    func isSelected(_ id: FileCategory.ID) -> Bool {
        selectedIDs.contains(id)
    }

    // MARK: Scanning

    func startScan() {
        guard !phase.isBusy else { return }

        let configuration = ScanConfiguration(downloadsAgeDays: Preferences.downloadsAgeDays)
        let categories = CategoryCatalog.categories(configuration: configuration)

        lastResult = nil
        selection = .overview
        phase = .scanning(ScanProgress(fractionCompleted: 0, message: "Starting scan…"))

        activeTask = Task { [weak self, scanManager] in
            let results = await scanManager.scan(categories: categories) { progress in
                Task { @MainActor in self?.receive(scanProgress: progress) }
            }
            guard let self else { return }
            guard !Task.isCancelled else {
                finishCancelledScan()
                return
            }
            finishScan(with: results)
        }
    }

    func cancelScan() {
        guard case .scanning = phase else { return }
        activeTask?.cancel()
    }

    private func receive(scanProgress: ScanProgress) {
        guard case .scanning(let current) = phase else { return }
        // Updates hop threads, so never let the bar move backwards.
        guard scanProgress.fractionCompleted >= current.fractionCompleted else { return }
        phase = .scanning(scanProgress)
    }

    private func finishScan(with results: [CategoryScanResult]) {
        scanResults = results
        selectedIDs = Set(results.filter { $0.isCleanable && $0.category.isSelectedByDefault }.map(\.id))
        phase = .ready
        activeTask = nil
    }

    private func finishCancelledScan() {
        phase = scanResults.isEmpty ? .idle : .ready
        activeTask = nil
    }

    // MARK: Selection

    func setSelected(_ isSelected: Bool, for id: FileCategory.ID) {
        guard cleanableResults.contains(where: { $0.id == id }) else { return }
        if isSelected {
            selectedIDs.insert(id)
        } else {
            selectedIDs.remove(id)
        }
    }

    func selectAll() {
        selectedIDs = Set(cleanableResults.map(\.id))
    }

    func selectNone() {
        selectedIDs = []
    }

    // MARK: Cleaning

    /// Step one of two: shows the confirmation dialog. Nothing is removed yet.
    func requestCleanup() {
        guard canClean else { return }
        isConfirmingCleanup = true
    }

    /// Step two: runs only from the dialog's Delete button.
    func confirmCleanup() {
        isConfirmingCleanup = false
        guard canClean else { return }

        let targets = selectedResults
        phase = .cleaning(CleanupProgress(
            fractionCompleted: 0,
            message: "Getting ready…",
            categoryID: nil,
            itemsProcessed: 0
        ))

        activeTask = Task { [weak self, cleanupManager] in
            let result = await cleanupManager.clean(targets) { progress in
                Task { @MainActor in self?.receive(cleanupProgress: progress) }
            }
            self?.finishCleanup(with: result)
        }
    }

    func cancelConfirmation() {
        isConfirmingCleanup = false
    }

    /// Stops after the item currently being removed. What was already removed stays removed.
    func stopCleanup() {
        guard case .cleaning = phase else { return }
        activeTask?.cancel()
    }

    private func receive(cleanupProgress: CleanupProgress) {
        guard case .cleaning(let current) = phase else { return }
        guard cleanupProgress.fractionCompleted >= current.fractionCompleted else { return }
        phase = .cleaning(cleanupProgress)
    }

    private func finishCleanup(with result: CleanupResult) {
        lastResult = result
        scanResults = []
        selectedIDs = []
        selection = .overview
        phase = .finished
        activeTask = nil
    }

    // MARK: Starting over

    func reset() {
        guard !phase.isBusy else { return }
        scanResults = []
        selectedIDs = []
        lastResult = nil
        selection = .overview
        phase = .idle
    }

    // MARK: Text

    var confirmationTitle: String {
        "You are about to remove"
    }

    var confirmationMessage: String {
        var lines: [String] = []
        lines.append(ByteFormat.string(selectedBytes))

        let categories = selectedResults.count
        lines.append("\(categories) \(categories == 1 ? "category" : "categories")")

        var itemLine = "\(selectedFileCount.formatted()) files"
        if selectedDockerObjectCount > 0 {
            itemLine += " + \(selectedDockerObjectCount.formatted()) Docker objects"
        }
        lines.append(itemLine)

        var message = lines.joined(separator: "\n")
        if selectionIncludesPermanentDeletion {
            message += "\n\nThis action cannot be undone."
        }
        if selectionIncludesTrashMoves {
            let names = selectedResults
                .filter { $0.category.disposal == .moveToTrash }
                .map(\.category.name)
                .formatted(.list(type: .and))
            message += "\n\n\(names) will be moved to the Trash, so you can still get them back."
        }
        return message
    }
}
