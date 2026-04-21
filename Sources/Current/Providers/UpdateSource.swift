import Foundation

struct CheckOptions {
    var greedyCasks: Bool = false
}

protocol UpdateSource: Sendable {
    /// Stable short id e.g. "brew", "npm", "pnpm", "bun".
    var id: String { get }
    var displayName: String { get }
    var iconSystemName: String { get }

    /// Fast check — returns false if tool isn't installed.
    func isAvailable() async -> Bool

    /// List outdated packages.
    func check(options: CheckOptions) async throws -> [UpdateItem]

    /// Upgrade a single package, streaming command output to `log`.
    func upgrade(_ item: UpdateItem, log: @escaping @Sendable (String) -> Void) async throws
}
