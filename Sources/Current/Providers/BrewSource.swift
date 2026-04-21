import Foundation

struct BrewSource: UpdateSource {
    let id = "brew"
    let displayName = "Homebrew"
    let iconSystemName = "mug"

    func isAvailable() async -> Bool { await Shell.hasTool("brew") }

    func check(options: CheckOptions) async throws -> [UpdateItem] {
        // Default (non-greedy) skips casks that auto-update themselves (Chrome, etc).
        var args = ["outdated", "--json=v2"]
        if options.greedyCasks { args.append("--greedy") }
        let res = try await Shell.run("brew", args)
        let data = Data(res.stdout.utf8)
        let decoded = try JSONDecoder().decode(BrewOutdated.self, from: data)

        let formulae = decoded.formulae.map {
            UpdateItem(
                sourceId: id,
                name: $0.name,
                currentVersion: $0.installed_versions.first ?? "?",
                latestVersion: $0.current_version
            )
        }
        let casks = decoded.casks.map {
            UpdateItem(
                sourceId: id,
                name: $0.name,
                currentVersion: $0.installed_versions ?? "?",
                latestVersion: $0.current_version
            )
        }
        return formulae + casks
    }

    func upgrade(_ item: UpdateItem, log: @escaping @Sendable (String) -> Void) async throws {
        try await Shell.stream("brew", ["upgrade", item.name], onLine: log)
    }

    // MARK: - Decoding

    private struct BrewOutdated: Decodable {
        let formulae: [Formula]
        let casks: [Cask]
    }
    private struct Formula: Decodable {
        let name: String
        let installed_versions: [String]
        let current_version: String
    }
    private struct Cask: Decodable {
        let name: String
        let installed_versions: String?
        let current_version: String
    }
}
