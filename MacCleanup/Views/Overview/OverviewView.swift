import SwiftUI

/// The main screen. Shows whichever step of the workflow is current.
struct OverviewView: View {
    @Environment(CleanupViewModel.self) private var viewModel

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle:
                IdleView()
            case .scanning(let progress):
                ProgressPanel(
                    symbolName: "magnifyingglass",
                    title: "Scanning…",
                    message: progress.message,
                    fraction: progress.fractionCompleted,
                    footnote: "Looking only. Nothing is being changed.",
                    buttonTitle: "Cancel Scan",
                    action: viewModel.cancelScan
                )
            case .ready:
                SummaryView()
            case .cleaning(let progress):
                ProgressPanel(
                    symbolName: "trash",
                    title: "Cleaning…",
                    message: progress.message,
                    fraction: progress.fractionCompleted,
                    footnote: progress.itemsProcessed > 0
                        ? "\(progress.itemsProcessed.formatted()) items processed"
                        : "Please keep the app open.",
                    buttonTitle: "Stop",
                    action: viewModel.stopCleanup
                )
            case .finished:
                ResultsView()
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Idle

private struct IdleView: View {
    @Environment(CleanupViewModel.self) private var viewModel
    @AppStorage(Preferences.downloadsAgeKey) private var downloadsAgeDays = Preferences.defaultDownloadsAgeDays

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "sparkles")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.tint)
                    .padding(.top, 40)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Free up space, safely")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Scan to see exactly what can be removed and how much space you'd get back. Nothing is deleted until you review it and confirm.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }

                Button {
                    viewModel.startScan()
                } label: {
                    Label("Scan System", systemImage: "magnifyingglass")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                VStack(alignment: .leading, spacing: 12) {
                    Stepper(value: $downloadsAgeDays, in: Preferences.downloadsAgeRange, step: 7) {
                        Text("Include Downloads older than **\(downloadsAgeDays) days**")
                    }
                    Divider()
                    Label("Documents, Desktop, Photos and other personal files are never touched.", systemImage: "hand.raised")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 480)
                .cardStyle()
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }
}

// MARK: - Progress (scanning and cleaning)

private struct ProgressPanel: View {
    let symbolName: String
    let title: String
    let message: String
    let fraction: Double
    let footnote: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: symbolName)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 26, weight: .semibold, design: .rounded))

            VStack(spacing: 8) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 380)
                HStack {
                    Text(message)
                        .lineLimit(1)
                    Spacer()
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            }

            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(buttonTitle, action: action)
                .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Summary

private struct SummaryView: View {
    @Environment(CleanupViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if viewModel.cleanableResults.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.cleanableResults.enumerated()), id: \.element.id) { index, result in
                                CategoryRow(result: result)
                                    .padding(.vertical, 12)
                                if index < viewModel.cleanableResults.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08))
                        }
                    }

                    if viewModel.hasRestrictedLocations {
                        PermissionNotice()
                    }

                    if !viewModel.otherResults.isEmpty {
                        OtherCategoriesNote(results: viewModel.otherResults)
                    }
                }
                .padding(24)
            }

            if !viewModel.cleanableResults.isEmpty {
                ActionBar(showsReviewButton: true)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Potential Cleanup")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Total Recoverable")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                BigStat(bytes: viewModel.selectedBytes)
                Text(headerDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.startScan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
        }
    }

    private var headerDetail: String {
        let selected = viewModel.selectedResults.count
        let found = viewModel.cleanableResults.count
        return "\(selected) of \(found) categories selected · \(ByteFormat.string(viewModel.totalFoundBytes)) found in total"
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.green)
            Text("Nothing to clean up")
                .font(.headline)
            Text("Your Mac is already tidy in all the places this app checks.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .cardStyle()
    }
}

/// Lists categories that had nothing to offer, so a missing row is never a mystery.
struct OtherCategoriesNote: View {
    let results: [CategoryScanResult]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(results) { result in
                    HStack(alignment: .firstTextBaseline) {
                        Text(result.category.name)
                            .font(.callout)
                        Spacer()
                        Text(reason(for: result))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text("\(results.count) \(results.count == 1 ? "category has" : "categories have") nothing to clean")
                .font(.callout.weight(.medium))
        }
        .cardStyle()
    }

    private func reason(for result: CategoryScanResult) -> String {
        switch result.status {
        case .scanned: return "Nothing to remove"
        case .notFound: return "Not found on this Mac"
        case .permissionDenied: return "Needs Full Disk Access"
        case .unavailable(let message): return message
        }
    }
}

// MARK: - Results

private struct ResultsView: View {
    @Environment(CleanupViewModel.self) private var viewModel
    @State private var showsFailures = false

    var body: some View {
        ScrollView {
            if let result = viewModel.lastResult {
                content(for: result)
            }
        }
    }

    @ViewBuilder
    private func content(for result: CleanupResult) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Image(systemName: result.wasStopped ? "pause.circle" : "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(result.wasStopped ? Color.orange : Color.green)
                    .symbolEffect(.bounce, value: result.filesRemoved)
                    .accessibilityHidden(true)
                Text(result.wasStopped ? "Cleanup Stopped" : "Cleanup Complete")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                if result.wasStopped {
                    Text("Everything removed before you stopped is gone; the rest was left alone.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 32)

            HStack(spacing: 14) {
                StatTile(title: "Recovered", value: ByteFormat.string(result.bytesRecovered), symbolName: "internaldrive")
                StatTile(
                    title: result.countsOnlyFiles ? "Files Removed" : "Items Removed",
                    value: result.filesRemoved.formatted(),
                    symbolName: "doc.on.doc"
                )
                StatTile(title: "Time", value: DurationFormat.string(result.duration), symbolName: "clock")
            }
            .frame(maxWidth: 640)

            if result.bytesMovedToTrash > 0 {
                Label(
                    "\(ByteFormat.string(result.bytesMovedToTrash)) was moved to the Trash. Empty the Trash to free that space.",
                    systemImage: "trash"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 640, alignment: .leading)
            }

            if !result.failures.isEmpty {
                failures(result.failures)
            }

            Button {
                viewModel.startScan()
            } label: {
                Label("Run New Scan", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func failures(_ failures: [CleanupFailure]) -> some View {
        DisclosureGroup(isExpanded: $showsFailures) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(failures.prefix(25)) { failure in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.itemName).font(.callout.weight(.medium))
                        Text(failure.reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if failures.count > 25 {
                    Text("and \(failures.count - 25) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Label(
                "\(failures.count) \(failures.count == 1 ? "item" : "items") couldn't be removed",
                systemImage: "exclamationmark.triangle"
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(.orange)
        }
        .frame(maxWidth: 640)
        .cardStyle()
    }
}
