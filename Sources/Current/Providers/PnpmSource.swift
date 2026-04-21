import Foundation

struct PnpmSource: UpdateSource {
    let id = "pnpm"
    let displayName = "pnpm (global)"
    let iconSystemName = "cube.box"

    func isAvailable() async -> Bool { await Shell.hasTool("pnpm") }

    func check(options: CheckOptions) async throws -> [UpdateItem] {
        let res = try await Shell.run("pnpm", ["outdated", "-g", "--format", "json"], throwsOnFail: false)
        guard !res.stdout.isEmpty, let data = res.stdout.data(using: .utf8) else { return [] }
        let decoded = (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
        return decoded.map { name, entry in
            UpdateItem(
                sourceId: id,
                name: name,
                currentVersion: entry.current ?? "?",
                latestVersion: entry.latest ?? "?"
            )
        }
    }

    func upgrade(_ item: UpdateItem, log: @escaping @Sendable (String) -> Void) async throws {
        try await Shell.stream("pnpm", ["add", "-g", "\(item.name)@latest"], onLine: log)
    }

    private struct Entry: Decodable {
        let current: String?
        let latest: String?
    }
}
