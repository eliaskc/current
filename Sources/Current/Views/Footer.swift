import SwiftUI

struct Footer: View {
    @EnvironmentObject var manager: UpdateManager

    var body: some View {
        HStack(spacing: 10) {
            if manager.stats.total > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10))
                    Text("\(manager.stats.lastWeek) this week")
                    Text("·")
                    Text("\(manager.stats.total) all time")
                    if manager.stats.failed > 0 {
                        Text("·")
                        Text("\(manager.stats.failed) failed")
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .help("Updates applied through Current")
            }

            Spacer()

            Button {
                Task { await manager.upgradeAll() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text(label).fontWeight(.semibold)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut(.defaultAction)
            .disabled(manager.visibleItems.isEmpty || manager.isBatchRunning)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var label: String {
        let n = manager.visibleItems.count
        if manager.isBatchRunning { return "Updating…" }
        return n > 0 ? "Update All (\(n))" : "Update All"
    }
}
