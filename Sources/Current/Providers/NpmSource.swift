import Foundation

struct NpmSource: UpdateSource {
    let id = "npm"
    let displayName = "npm (global)"
    let iconSystemName = "shippingbox.fill"

    func isAvailable() async -> Bool { await Shell.hasTool("npm") }

    func check(options: CheckOptions) async throws -> [UpdateItem] {
        // `npm outdated` exits with code 1 when outdated packages exist — don't throw.
        let res = try await Shell.run("npm", ["outdated", "-g", "--json"], throwsOnFail: false)
        guard !res.stdout.isEmpty, let data = res.stdout.data(using: .utf8) else { return [] }
        let decoded = (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
        return decoded.map { name, entry in
            UpdateItem(
                sourceId: id,
                name: name,
                currentVersion: entry.current ?? "?",
                latestVersion: entry.latest ?? entry.wanted ?? "?"
            )
        }
    }

    func upgrade(_ item: UpdateItem, log: @escaping @Sendable (String) -> Void) async throws {
        try await Shell.stream("npm", ["install", "-g", "\(item.name)@latest"], onLine: log)
    }

    private struct Entry: Decodable {
        let current: String?
        let wanted: String?
        let latest: String?
    }
}
