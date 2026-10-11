import SwiftUI

struct SettingsView: View {
    @AppStorage(Preferences.downloadsAgeKey) private var downloadsAgeDays = Preferences.defaultDownloadsAgeDays

    var body: some View {
        Form {
            Section {
                Stepper(value: $downloadsAgeDays, in: Preferences.downloadsAgeRange, step: 7) {
                    LabeledContent("Downloads older than") {
                        Text("\(downloadsAgeDays) days")
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Scan")
            } footer: {
                Text("Items in Downloads that were added and last changed longer ago than this are offered for cleanup. They are moved to the Trash, never deleted outright. Takes effect on the next scan.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
