import SwiftUI

/// Explains, in plain language, what the app will and won't do.
struct SafetyView: View {
    private let steps: [(symbol: String, title: String, detail: String)] = [
        ("magnifyingglass", "Scan", "Looks at a fixed list of cleanup locations. Reading only: nothing is changed."),
        ("list.bullet.rectangle", "Review", "See the size, location and a preview of every category."),
        ("checkmark.square", "Select", "Choose exactly which categories to clean."),
        ("exclamationmark.bubble", "Confirm", "A dialog states what will be removed. Nothing happens until you press Delete."),
        ("trash", "Delete", "Items are removed with live progress, and you can stop at any time."),
    ]

    private let neverTouched = [
        "Desktop and Documents",
        "Pictures, Movies and Music, including Photos and Music libraries",
        "iCloud Drive and other synced folders",
        "Mail, Messages, Keychains and app settings",
        "The system, /Applications and other users' files",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Safety")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))

                VStack(alignment: .leading, spacing: 16) {
                    Text("How cleanup works")
                        .font(.headline)
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            CategoryIcon(symbolName: step.symbol)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(index + 1). \(step.title)").font(.callout.weight(.semibold))
                                Text(step.detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Never touched", systemImage: "hand.raised")
                        .font(.headline)
                    ForEach(neverTouched, id: \.self) { item in
                        Label(item, systemImage: "checkmark")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("These rules are checked again just before every item is removed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Your own files go to the Trash", systemImage: "arrow.uturn.backward")
                        .font(.headline)
                    Text("Old Downloads and Xcode Archives are moved to the Trash instead of being deleted, so a mistake can be undone. Caches, logs and other regenerable data are deleted for good.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Permissions", systemImage: "lock.shield")
                        .font(.headline)
                    Text("The app asks for nothing by default. A few macOS-protected folders (the Trash, Safari's cache) can only be read if you allow Full Disk Access. That's optional, and everything else works without it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Full Disk Access Settings") {
                        SystemSettingsLink.openFullDiskAccess()
                    }
                    .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .padding(24)
        }
    }
}
