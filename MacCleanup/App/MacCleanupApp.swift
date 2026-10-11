import SwiftUI

@main
struct MacCleanupApp: App {
    @State private var viewModel = CleanupViewModel()

    var body: some Scene {
        Window("Mac Cleanup Assistant", id: "main") {
            ContentView()
                .environment(viewModel)
        }
        .defaultSize(width: 1000, height: 660)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Cleanup") {
                Button("Scan System") { viewModel.startScan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(viewModel.phase.isBusy)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
