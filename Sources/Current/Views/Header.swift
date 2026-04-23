import SwiftUI

struct Header: View {
    @EnvironmentObject var manager: UpdateManager

    var body: some View {
        HStack(spacing: 8) {
            Text("Updates").font(.headline)
            if manager.visibleCount > 0 {
                Text("\(manager.visibleCount)")
                    .font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
            Spacer()

            if let last = manager.lastRefresh {
                Text(RelativeTime.string(from: last))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("Last checked")
            }

            // Fixed-size slot so swapping button ↔ spinner doesn't shift the header.
            ZStack {
                if manager.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                } else {
                    Button {
                        Task { await manager.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .hoverHighlight()
                    .help("Check now")
                }
            }
            .frame(width: 18, height: 18)

            Button {
                NotificationCenter.default.post(name: .currentOpenPreferences, object: nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .hoverHighlight()
            .help("Preferences")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}
