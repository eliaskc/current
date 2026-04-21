import SwiftUI

struct RootView: View {
    @EnvironmentObject var manager: UpdateManager

    var body: some View {
        VStack(spacing: 0) {
            Header()
            Divider()

            if manager.visibleItems.isEmpty {
                EmptyState(isRefreshing: manager.isRefreshing)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.visibleItems) { item in
                            UpdateRow(item: item)
                            Divider().opacity(0.4)
                        }
                    }
                }
            }

            Divider()
            Footer()
        }
        .frame(width: 340, height: 480)
    }
}

private struct EmptyState: View {
    let isRefreshing: Bool
    var body: some View {
        VStack(spacing: 8) {
            if isRefreshing {
                ProgressView()
                Text("Checking for updates…").foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                Text("You're all caught up").font(.headline)
                Text("No updates across your sources.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
