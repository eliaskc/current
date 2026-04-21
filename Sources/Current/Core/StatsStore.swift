import Foundation

struct UpgradeEvent: Codable, Identifiable {
    let id: UUID
    let sourceId: String
    let name: String
    let fromVersion: String
    let toVersion: String
    let timestamp: Date
    let success: Bool

    init(sourceId: String, name: String, fromVersion: String, toVersion: String, success: Bool, timestamp: Date = Date()) {
        self.id = UUID()
        self.sourceId = sourceId
        self.name = name
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.timestamp = timestamp
        self.success = success
    }
}

/// Append-only log of upgrade attempts. Capped at `maxEvents`.
enum StatsStore {
    private static let key = "current.upgradeHistory"
    private static let maxEvents = 1000

    static func load() -> [UpgradeEvent] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let events = try? JSONDecoder().decode([UpgradeEvent].self, from: data) else { return [] }
        return events
    }

    static func save(_ events: [UpgradeEvent]) {
        let trimmed = events.suffix(maxEvents)
        if let data = try? JSONEncoder().encode(Array(trimmed)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func append(_ event: UpgradeEvent) {
        var all = load()
        all.append(event)
        save(all)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Summaries

    struct Summary {
        var total: Int
        var lastWeek: Int
        var failed: Int
    }

    static func summary(from events: [UpgradeEvent] = load()) -> Summary {
        let successful = events.filter(\.success)
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        return Summary(
            total: successful.count,
            lastWeek: successful.filter { $0.timestamp >= weekAgo }.count,
            failed: events.filter { !$0.success }.count
        )
    }
}
