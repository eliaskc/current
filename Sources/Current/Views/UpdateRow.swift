import SwiftUI

struct UpdateRow: View {
    @EnvironmentObject var manager: UpdateManager
    let item: UpdateItem
    @State private var expanded = false
    @State private var hovering = false

    private var status: RowStatus { manager.status[item.id] ?? .idle }
    private var hasLog: Bool { (manager.logs[item.id]?.isEmpty == false) }

    /// Split a scoped npm name (`@scope/name`) into its parts so we can render
    /// the scope as a muted prefix line above the bold bare name. Non-scoped
    /// names return `(nil, item.name)` and render as a single line.
    private var nameParts: (scope: String?, bare: String) {
        let n = item.name
        if n.hasPrefix("@"), let slash = n.firstIndex(of: "/") {
            return (String(n[...slash]), String(n[n.index(after: slash)...]))
        }
        return (nil, n)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                SourceBadge(sourceId: item.sourceId)

                VStack(alignment: .leading, spacing: 1) {
                    if let scope = nameParts.scope {
                        Text(scope)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack(spacing: 6) {
                        Text(nameParts.bare)
                            .font(.system(.body, design: .monospaced).weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if hasLog {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text("\(item.currentVersion) → \(item.latestVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .help(item.name)

                Spacer()

                trailingCluster
            }
            .contentShape(Rectangle())
            .onTapGesture { if hasLog { expanded.toggle() } }

            if expanded && hasLog, let log = manager.logs[item.id] {
                LogView(log: log)
            }

            if case .failure(let msg) = status, !expanded {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onHover { hovering = $0 }
        .background(hovering ? Color.secondary.opacity(0.06) : Color.clear)
    }

    // MARK: - Trailing cluster

    /// Shared height so Skip / Update / icon buttons line up perfectly.
    private let rowControlHeight: CGFloat = 22

    @ViewBuilder private var trailingCluster: some View {
        switch status {
        case .idle:
            HStack(spacing: 6) {
                // Ignore — reveals on row hover. Frame is reserved always so
                // the Skip/Update cluster doesn't slide when the bell fades in.
                Button { manager.ignore(item) } label: {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 11))
                        .frame(width: 18, height: rowControlHeight)
                        .opacity(hovering ? 1 : 0)
                        .animation(.easeOut(duration: 0.12), value: hovering)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .hoverHighlight(expand: 2)
                .help("Stop showing updates for \(item.name)")

                // Skip — subtle outlined secondary action
                Button { manager.skip(item) } label: {
                    Text("Skip")
                        .font(.caption)
                        .frame(width: 36)
                }
                .buttonStyle(ChipButtonStyle())
                .frame(height: rowControlHeight)
                .fixedSize()
                .help("Skip \(item.latestVersion) (re-appears when a newer version ships)")

                // Update — the clear CTA for this row
                Button { Task { await manager.upgrade(item) } } label: {
                    Text("Update")
                        .font(.caption.weight(.semibold))
                        .frame(width: 48)
                }
                .buttonStyle(ChipButtonStyle(prominent: true))
                .frame(height: rowControlHeight)
                .fixedSize()
            }

        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .help("Queued")
                .frame(height: rowControlHeight)

        case .running:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: rowControlHeight)

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Updated")
                .frame(height: rowControlHeight)

        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("Failed")
                .frame(height: rowControlHeight)
        }
    }
}

// MARK: - Source badge

/// Colored pill with the package-manager name. Shared with Preferences.
struct SourceBadge: View {
    let sourceId: String
    var size: Size = .regular

    enum Size { case regular, large }

    var body: some View {
        Text(sourceId)
            .font(.system(size: size == .large ? 11 : 9.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .tracking(0.3)
            .padding(.horizontal, size == .large ? 8 : 6)
            .frame(minWidth: size == .large ? 44 : 38,
                   minHeight: size == .large ? 22 : 18)
            .background(
                RoundedRectangle(cornerRadius: size == .large ? 6 : 5)
                    .fill(sourceTint(sourceId))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size == .large ? 6 : 5)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            )
    }
}

private struct LogView: View {
    let log: String
    var body: some View {
        ScrollView {
            Text(log)
                .font(.system(size: 10, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 140)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.4)))
    }
}
