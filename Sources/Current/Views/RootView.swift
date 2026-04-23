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
                        let items = manager.visibleItems
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            UpdateRow(item: item)
                            if idx < items.count - 1 {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                    .background(OverlayScrollerStyle())
                }
                .scrollIndicators(.automatic)
            }

            Divider()
            Footer()
        }
        .frame(width: 400, height: 420)
    }
}

/// Force the enclosing `NSScrollView` into the thin, auto-hiding overlay
/// scroller style even when the user has "Always show scroll bars" set in
/// System Settings. Without this we get the chunky legacy scroller that
/// eats a full gutter on the right edge of the popover.
private struct OverlayScrollerStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { [weak v] in
            guard let scroll = v?.enclosingScrollView else { return }
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            scroll.verticalScroller?.knobStyle = .default
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
