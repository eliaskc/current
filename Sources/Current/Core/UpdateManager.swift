import Foundation
import SwiftUI

@MainActor
final class UpdateManager: ObservableObject {
    // Data
    @Published private(set) var items: [UpdateItem] = []
    @Published private(set) var status: [UpdateItem.ID: RowStatus] = [:]
    @Published private(set) var logs: [UpdateItem.ID: String] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isBatchRunning = false
    @Published private(set) var sourceStates: [SourceState] = []
    @Published private(set) var stats: StatsStore.Summary = StatsStore.summary()

    // Persisted user preferences
    @Published var skippedVersions: [UpdateItem.ID: String] = Persistence.loadSkipped() {
        didSet { Persistence.saveSkipped(skippedVersions); notifyMenuBar() }
    }
    @Published var ignoredPackages: Set<UpdateItem.ID> = Persistence.loadIgnored() {
        didSet { Persistence.saveIgnored(ignoredPackages); notifyMenuBar() }
    }
    @AppStorage("current.refreshIntervalHours") var refreshIntervalHours: Int = 6
    @AppStorage("current.greedyCasks") var greedyCasks: Bool = false
    @Published var enabledSources: Set<String> = Persistence.loadEnabledSources() {
        didSet { Persistence.saveEnabledSources(enabledSources); notifyMenuBar() }
    }

    // Providers
    private let sources: [any UpdateSource] = [BrewSource(), NpmSource(), PnpmSource()]

    private var refreshInterval: TimeInterval { TimeInterval(refreshIntervalHours) * 3600 }

    init() {
        // First launch: enable everything by default.
        if !UserDefaults.standard.bool(forKey: "current.enabledSourcesInitialized") {
            enabledSources = Set(sources.map(\.id))
            UserDefaults.standard.set(true, forKey: "current.enabledSourcesInitialized")
        }
    }

    // MARK: - Derived

    var visibleItems: [UpdateItem] {
        items.filter { !isSkipped($0) && !ignoredPackages.contains($0.id) }
             .sorted { ($0.sourceId, $0.name) < ($1.sourceId, $1.name) }
    }
    var visibleCount: Int { visibleItems.count }

    /// Count shown in the menu bar badge. Completed rows can remain visible in
    /// the open popover as confirmation, but they should not keep advertising
    /// outstanding work in the menu bar.
    var pendingCount: Int { pendingItems.count }

    /// Visible items that still need to be upgraded — excludes anything in
    /// `.success`. Drives the "Update All" button's count and disabled state
    /// so we don't pretend there's work left when everything's green.
    var pendingItems: [UpdateItem] {
        visibleItems.filter { status[$0.id] != .success }
    }
    var isWorking: Bool { isRefreshing || isBatchRunning }

    func isSkipped(_ item: UpdateItem) -> Bool {
        skippedVersions[item.id] == item.latestVersion
    }

    /// All known providers (used by preferences, regardless of enabled state).
    var allSources: [any UpdateSource] { sources }

    // MARK: - Refresh

    func refreshIfStale() async {
        guard let last = lastRefresh else { await refresh(); return }
        if Date().timeIntervalSince(last) > refreshInterval { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        notifyMenuBar()
        defer {
            isRefreshing = false
            notifyMenuBar()
        }

        let enabled = enabledSources
        let greedy = greedyCasks

        var results: [(id: String, available: Bool, items: [UpdateItem])] = []
        await withTaskGroup(of: (String, Bool, [UpdateItem]).self) { group in
            for src in sources {
                group.addTask {
                    let available = await src.isAvailable()
                    guard available, enabled.contains(src.id) else {
                        return (src.id, available, [])
                    }
                    // Pass greedy flag where applicable.
                    let opts = CheckOptions(greedyCasks: greedy)
                    let list = (try? await src.check(options: opts)) ?? []
                    return (src.id, available, list)
                }
            }
            for await r in group { results.append(r) }
        }

        var merged: [UpdateItem] = []
        var states: [SourceState] = []
        for src in sources {
            let r = results.first { $0.id == src.id } ?? (src.id, false, [])
            merged.append(contentsOf: r.items)
            let availability: SourceAvailability =
                !r.available ? .unavailable :
                !enabled.contains(src.id) ? .disabled :
                .available
            states.append(SourceState(
                id: src.id,
                displayName: src.displayName,
                iconSystemName: src.iconSystemName,
                tint: sourceTint(src.id),
                availability: availability,
                itemCount: r.items.count
            ))
        }

        items = merged
        sourceStates = states

        let ids = Set(merged.map(\.id))
        status = status.filter { ids.contains($0.key) }
        logs = logs.filter { ids.contains($0.key) }
        lastRefresh = Date()
        notifyMenuBar()
    }

    // MARK: - Actions

    func skip(_ item: UpdateItem) { skippedVersions[item.id] = item.latestVersion }
    func unskip(_ id: UpdateItem.ID) { skippedVersions.removeValue(forKey: id) }

    func ignore(_ item: UpdateItem) { ignoredPackages.insert(item.id) }
    func unignore(_ id: UpdateItem.ID) { ignoredPackages.remove(id) }

    func toggleSource(_ id: String, enabled: Bool) {
        if enabled { enabledSources.insert(id) } else { enabledSources.remove(id) }
        Task { await refresh() }
    }

    // MARK: - Upgrade

    func upgrade(_ item: UpdateItem) async {
        await runUpgrade(item)
    }

    func upgradeAll() async {
        await upgrade(items: pendingItems)
    }

    /// Drop everything currently sitting in `.success`. Called when the
    /// popover closes so a fresh open doesn't show stale "done" rows.
    func clearCompleted() {
        let doneIds = status.compactMap { $0.value == .success ? $0.key : nil }
        guard !doneIds.isEmpty else { return }
        let done = Set(doneIds)
        items.removeAll { done.contains($0.id) }
        for id in doneIds {
            status.removeValue(forKey: id)
            logs.removeValue(forKey: id)
        }
        notifyMenuBar()
    }

    func upgrade(items targets: [UpdateItem]) async {
        guard !isBatchRunning else { return }
        isBatchRunning = true
        notifyMenuBar()
        defer {
            isBatchRunning = false
            notifyMenuBar()
        }

        for t in targets { status[t.id] = .queued }
        notifyMenuBar()

        for t in targets {
            // Allow in-flight cancellation: if user cleared a row, skip.
            guard status[t.id] == .queued else { continue }
            await runUpgrade(t)
        }
    }

    private func source(for item: UpdateItem) -> (any UpdateSource)? {
        sources.first { $0.id == item.sourceId }
    }

    private func runUpgrade(_ item: UpdateItem) async {
        guard let source = source(for: item) else {
            status[item.id] = .failure("No provider for \(item.sourceId)")
            return
        }
        status[item.id] = .running
        logs[item.id] = ""
        notifyMenuBar()
        let id = item.id
        do {
            try await source.upgrade(item) { [weak self] line in
                Task { @MainActor [weak self] in
                    self?.logs[id, default: ""] += line + "\n"
                }
            }
            status[id] = .success
            recordUpgrade(item, success: true)
            // Keep the row in place as a "done" state. It disappears on the
            // next refresh when the source stops reporting it as outdated.
            notifyMenuBar()
        } catch {
            status[id] = .failure(error.localizedDescription)
            recordUpgrade(item, success: false)
            notifyMenuBar()
        }
    }

    private func recordUpgrade(_ item: UpdateItem, success: Bool) {
        let event = UpgradeEvent(
            sourceId: item.sourceId, name: item.name,
            fromVersion: item.currentVersion, toVersion: item.latestVersion,
            success: success
        )
        StatsStore.append(event)
        stats = StatsStore.summary()
    }

    // MARK: - Helpers

    private func notifyMenuBar() {
        NotificationCenter.default.post(name: .currentMenuBarShouldUpdate, object: nil)
    }
}

// MARK: - Colors per source (shared with views)

func sourceTint(_ id: String) -> Color {
    switch id {
    case "brew": return .orange
    case "npm":  return .red
    case "pnpm": return .yellow
    case "bun":  return .pink
    default:     return .gray
    }
}

// MARK: - Persistence

private enum Persistence {
    private static let skippedKey = "current.skippedVersions"
    private static let ignoredKey = "current.ignoredPackages"
    private static let enabledKey = "current.enabledSources"

    static func loadSkipped() -> [UpdateItem.ID: String] {
        guard let data = UserDefaults.standard.data(forKey: skippedKey),
              let v = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return v
    }
    static func saveSkipped(_ v: [UpdateItem.ID: String]) {
        if let data = try? JSONEncoder().encode(v) {
            UserDefaults.standard.set(data, forKey: skippedKey)
        }
    }
    static func loadIgnored() -> Set<UpdateItem.ID> {
        guard let data = UserDefaults.standard.data(forKey: ignoredKey),
              let v = try? JSONDecoder().decode(Set<String>.self, from: data) else { return [] }
        return v
    }
    static func saveIgnored(_ v: Set<UpdateItem.ID>) {
        if let data = try? JSONEncoder().encode(v) {
            UserDefaults.standard.set(data, forKey: ignoredKey)
        }
    }
    static func loadEnabledSources() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: enabledKey),
              let v = try? JSONDecoder().decode(Set<String>.self, from: data) else { return [] }
        return v
    }
    static func saveEnabledSources(_ v: Set<String>) {
        if let data = try? JSONEncoder().encode(v) {
            UserDefaults.standard.set(data, forKey: enabledKey)
        }
    }
}
