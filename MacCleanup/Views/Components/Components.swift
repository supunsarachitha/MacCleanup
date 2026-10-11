import SwiftUI
import AppKit

// MARK: - Card style

extension View {
    /// The rounded container used for every grouped block of content.
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            }
    }
}

// MARK: - Large statistic

/// A big number with a small unit, as used for the totals.
struct BigStat: View {
    let bytes: Int64
    var size: CGFloat = 64

    var body: some View {
        let parts = ByteFormat.parts(bytes)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(parts.value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text(parts.unit)
                .font(.system(size: size * 0.4, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ByteFormat.string(bytes))
    }
}

/// A labelled figure for the results screen.
struct StatTile: View {
    let title: String
    let value: String
    let symbolName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbolName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Category icon

struct CategoryIcon: View {
    let symbolName: String
    var tint: Color = .accentColor

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Category row

/// One line of the summary: checkbox, icon, name and size.
struct CategoryRow: View {
    @Environment(CleanupViewModel.self) private var viewModel
    let result: CategoryScanResult

    var body: some View {
        HStack(spacing: 14) {
            Toggle(result.category.name, isOn: Binding(
                get: { viewModel.isSelected(result.id) },
                set: { viewModel.setSelected($0, for: result.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            CategoryIcon(symbolName: result.category.symbolName)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.category.name)
                    .font(.headline)
                Text(result.category.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormat.string(result.totalSize))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(result.category.countsFiles
                     ? "\(result.fileCount.formatted()) files"
                     : "\(result.fileCount.formatted()) objects")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Action bar

/// The total and the two main actions, pinned to the bottom of Overview and Review.
struct ActionBar: View {
    @Environment(CleanupViewModel.self) private var viewModel
    var showsReviewButton = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total Recoverable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ByteFormat.string(viewModel.selectedBytes))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Spacer()

            Button("Select None") { viewModel.selectNone() }
                .buttonStyle(.link)
                .disabled(viewModel.selectedIDs.isEmpty)

            if showsReviewButton {
                Button("Review Details") { viewModel.selection = .review }
                    .controlSize(.large)
            }

            Button("Clean Selected") { viewModel.requestCleanup() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canClean)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Full Disk Access notice

enum SystemSettingsLink {
    static let fullDiskAccess = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")

    @MainActor
    static func openFullDiskAccess() {
        guard let url = fullDiskAccess else { return }
        NSWorkspace.shared.open(url)
    }
}

struct PermissionNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Some locations couldn't be read")
                    .font(.headline)
                Text("macOS protects a few folders, such as the Trash and Safari's cache. This is optional: you can allow access in Privacy & Security ▸ Full Disk Access, or leave it and clean everything else.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Full Disk Access Settings") {
                    SystemSettingsLink.openFullDiskAccess()
                }
                .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
