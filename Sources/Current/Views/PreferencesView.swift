import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var manager: UpdateManager

    var body: some View {
        TabView {
            GeneralPrefs()
                .tabItem { Label("General", systemImage: "gearshape") }
            IgnoredPrefs()
                .tabItem { Label("Ignored Packages", systemImage: "bell.slash") }
            SkippedPrefs()
                .tabItem { Label("Skipped Versions", systemImage: "forward.end") }
        }
        .padding(20)
        .frame(width: 540, height: 560)
    }
}

// MARK: - General (schedule + homebrew + sources)

private struct GeneralPrefs: View {
    @EnvironmentObject var manager: UpdateManager

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Check every", selection: $manager.refreshIntervalHours) {
                    Text("1 hour").tag(1)
                    Text("6 hours").tag(6)
                    Text("12 hours").tag(12)
                    Text("1 day").tag(24)
                    Text("1 week").tag(168)
                }
                .pickerStyle(.menu)
            }

            Section("Homebrew") {
                Toggle("Include casks that auto-update themselves", isOn: $manager.greedyCasks)
                Text("When off, Chrome / Slack / etc. don't spam the list because they update themselves via Sparkle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sources") {
                ForEach(manager.sourceStates) { state in
                    SourceRow(state: state)
                }
                Text("Sources greyed out as *Not installed* aren't on your shell PATH. Install them normally, then Check Now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private struct SourceRow: View {
        @EnvironmentObject var manager: UpdateManager
        let state: SourceState

        var body: some View {
            HStack(spacing: 10) {
                SourceBadge(sourceId: state.id, size: .large)
                    .opacity(state.availability == .unavailable ? 0.4 : 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.displayName).font(.body)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { manager.enabledSources.contains(state.id) },
                    set: { manager.toggleSource(state.id, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(state.availability == .unavailable)
            }
        }

        private var subtitle: String {
            switch state.availability {
            case .available:
                return state.itemCount == 0
                    ? "Ready · nothing outdated"
                    : "Ready · \(state.itemCount) outdated"
            case .disabled:    return "Disabled"
            case .unavailable: return "Not installed"
            }
        }
    }
}

// MARK: - Ignored packages

private struct IgnoredPrefs: View {
    @EnvironmentObject var manager: UpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ignored Packages").font(.title3.bold())
            Text("These packages never appear in the updates list.")
                .font(.caption).foregroundStyle(.secondary)

            if manager.ignoredPackages.isEmpty {
                EmptyPanel(text: "No ignored packages.")
            } else {
                List {
                    ForEach(Array(manager.ignoredPackages).sorted(), id: \.self) { id in
                        IdRow(id: id) { manager.unignore(id) }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - Skipped versions

private struct SkippedPrefs: View {
    @EnvironmentObject var manager: UpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skipped Versions").font(.title3.bold())
            Text("A skip is lifted automatically when a newer version is released.")
                .font(.caption).foregroundStyle(.secondary)

            if manager.skippedVersions.isEmpty {
                EmptyPanel(text: "No skipped versions.")
            } else {
                List {
                    ForEach(manager.skippedVersions.keys.sorted(), id: \.self) { id in
                        IdRow(id: id, trailing: manager.skippedVersions[id]) {
                            manager.unskip(id)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

// MARK: - Shared bits

private struct IdRow: View {
    let id: String
    var trailing: String? = nil
    let onRemove: () -> Void

    var body: some View {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        let sourceId = parts.first ?? ""
        let name = parts.count > 1 ? parts[1] : id

        HStack(spacing: 10) {
            SourceBadge(sourceId: sourceId)
            Text(name).font(.system(.body, design: .monospaced))
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(.secondary)
            }
            Button("Remove", action: onRemove).buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

private struct EmptyPanel: View {
    let text: String
    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.3)))
    }
}
