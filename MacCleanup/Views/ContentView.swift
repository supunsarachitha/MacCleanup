import SwiftUI

struct ContentView: View {
    @Environment(CleanupViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            Group {
                switch viewModel.selection {
                case .overview: OverviewView()
                case .review: ReviewView()
                case .safety: SafetyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 820, minHeight: 560)
        .animation(.smooth, value: viewModel.phase)
        .alert(viewModel.confirmationTitle, isPresented: $viewModel.isConfirmingCleanup) {
            Button("Cancel", role: .cancel) { viewModel.cancelConfirmation() }
            Button("Delete", role: .destructive) { viewModel.confirmCleanup() }
        } message: {
            Text(viewModel.confirmationMessage)
        }
    }
}

struct SidebarView: View {
    @Environment(CleanupViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        List(selection: $viewModel.selection) {
            Section {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.symbolName)
                        .tag(item)
                        .disabled(item == .review && !viewModel.canReview)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Label("Nothing is deleted without your confirmation.", systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }
}

private extension CleanupViewModel {
    /// The review screen only makes sense while there are scan results to review.
    var canReview: Bool {
        phase == .ready
    }
}
