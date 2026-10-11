import SwiftUI

/// Expandable details for every category: location, size, file count and a short preview.
struct ReviewView: View {
    @Environment(CleanupViewModel.self) private var viewModel
    @State private var expanded: Set<FileCategory.ID> = []

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.cleanableResults.isEmpty {
                ContentUnavailableView(
                    "Nothing to review",
                    systemImage: "checkmark.circle",
                    description: Text("Run a scan from Overview to see what can be cleaned.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Review Details")
                                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                                Text("Expand a category to see where it lives and what's in it.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(allExpanded ? "Collapse All" : "Expand All") {
                                expanded = allExpanded ? [] : Set(viewModel.cleanableResults.map(\.id))
                            }
                        }

                        ForEach(viewModel.cleanableResults) { result in
                            CategoryCard(result: result, isExpanded: binding(for: result.id))
                        }

                        if !viewModel.otherResults.isEmpty {
                            OtherCategoriesNote(results: viewModel.otherResults)
                        }
                    }
                    .padding(24)
                }
                ActionBar()
            }
        }
        .onChange(of: viewModel.phase) { _, phase in
            if phase != .ready { viewModel.selection = .overview }
        }
    }

    private var allExpanded: Bool {
        !viewModel.cleanableResults.isEmpty && expanded.count == viewModel.cleanableResults.count
    }

    private func binding(for id: FileCategory.ID) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
}

private struct CategoryCard: View {
    @Environment(CleanupViewModel.self) private var viewModel
    let result: CategoryScanResult
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                Divider().padding(.vertical, 14)
                details
            }
        }
        .cardStyle()
    }

    private var header: some View {
        HStack(spacing: 14) {
            Toggle(result.category.name, isOn: Binding(
                get: { viewModel.isSelected(result.id) },
                set: { viewModel.setSelected($0, for: result.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            Button {
                withAnimation(.smooth(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)

                    CategoryIcon(symbolName: result.category.symbolName)

                    Text(result.category.name)
                        .font(.headline)

                    Spacer()

                    Text(ByteFormat.string(result.totalSize))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(result.category.name), \(ByteFormat.string(result.totalSize))")
            .accessibilityHint(isExpanded ? "Collapse details" : "Expand details")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(result.category.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 10) {
                GridRow {
                    label("Location")
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(result.category.locationDescriptions, id: \.self) { path in
                            Text(path)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                GridRow {
                    label("Size")
                    Text(ByteFormat.string(result.totalSize)).font(.callout).monospacedDigit()
                }
                GridRow {
                    label(result.category.countsFiles ? "Files" : "Objects")
                    Text(result.fileCount.formatted()).font(.callout).monospacedDigit()
                }
            }

            if !result.samples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    label("Preview")
                    ForEach(result.samples) { sample in
                        HStack {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(sample.name)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let detail = sample.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ByteFormat.string(sample.size))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if result.unlistedItemCount > 0 {
                        Text("and \(result.unlistedItemCount.formatted()) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let warning = result.category.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if result.protectedItemsSkipped > 0 {
                Label(
                    "\(result.protectedItemsSkipped) protected \(result.protectedItemsSkipped == 1 ? "item was" : "items were") left out.",
                    systemImage: "lock.shield"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            if result.hasRestrictedLocations {
                Label("Some items here couldn't be read, so the real total may be larger.", systemImage: "lock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}
