import Foundation

struct UpdateItem: Identifiable, Hashable, Codable {
    /// "<sourceId>:<name>" — stable across refreshes.
    let id: String
    let sourceId: String
    let name: String
    let currentVersion: String
    let latestVersion: String

    init(sourceId: String, name: String, currentVersion: String, latestVersion: String) {
        self.sourceId = sourceId
        self.name = name
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.id = "\(sourceId):\(name)"
    }
}
