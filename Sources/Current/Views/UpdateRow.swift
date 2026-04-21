import SwiftUI

struct UpdateRow: View {
    @EnvironmentObject var manager: UpdateManager
    let item: UpdateItem
    @State private var expanded = false
    @State private var hovering = false

    private var status: RowStatus { manager.status[item.id] ?? .idle }
    private var hasLog: Bool { (manager.logs[item.id]?.isEmpty == false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                SourceBadge(sourceId: item.sourceId)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(.body, design: .monospaced))
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
                // Ignore — subtle always-visible icon
                Button { manager.ignore(item) } label: {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 11))
                        .frame(width: 18, height: rowControlHeight)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .help("Stop showing updates for \(item.name)")

                // Skip — subtle outlined secondary action
                Button { manager.skip(item) } label: {
                    Text("Skip")
                        .font(.caption)
                        .frame(width: 36)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.secondary)
                .frame(height: rowControlHeight)
                .fixedSize()
                .help("Skip \(item.latestVersion) (re-appears when a newer version ships)")

                // Update — the clear CTA for this row
                Button { Task { await manager.upgrade(item) } } label: {
                    Text("Update")
                        .font(.caption.weight(.semibold))
                        .frame(width: 48)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(height: rowControlHeight)
                .fixedSize()
            }

        case .queued:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .help("Queued")
                .frame(height: rowControlHeight)

        case .running:
            HStack(spacing: 6) {
                LogToggleButton(expanded: $expanded, height: rowControlHeight)
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 16, height: rowControlHeight)
            }

        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Updated")
                .frame(height: rowControlHeight)

        case .failure:
            HStack(spacing: 6) {
                LogToggleButton(expanded: $expanded, height: rowControlHeight)
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Failed")
                    .frame(height: rowControlHeight)
            }
        }
    }
}

// MARK: - Pieces

private struct LogToggleButton: View {
    @Binding var expanded: Bool
    let height: CGFloat
    var body: some View {
        Button { expanded.toggle() } label: {
            Text(expanded ? "Hide" : "Log").font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(height: height)
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
