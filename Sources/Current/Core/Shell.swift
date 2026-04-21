import Foundation

/// Runs shell commands via the user's login shell so tools installed by
/// Homebrew, nvm, mise, etc. are on PATH — exactly like opening Terminal.
enum Shell {
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var ok: Bool { exitCode == 0 }
    }

    enum ShellError: Error, LocalizedError {
        case nonZeroExit(Int32, stderr: String)
        var errorDescription: String? {
            switch self {
            case .nonZeroExit(let code, let err):
                return "Exit \(code): \(err.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        }
    }

    /// Build a single shell command string that runs `cmd args…` through the
    /// user's login shell (`zsh -ilc`) so PATH matches their Terminal.
    private static func makeProcess(_ cmd: String, _ args: [String]) -> Process {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // -i interactive (loads .zshrc), -l login, -c command
        let joined = ([cmd] + args).map { shellQuote($0) }.joined(separator: " ")
        proc.arguments = ["-ilc", joined]
        return proc
    }

    private static func shellQuote(_ s: String) -> String {
        if s.range(of: "[^A-Za-z0-9_\\-./=:]", options: .regularExpression) == nil { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Run to completion, collecting stdout/stderr. Throws on non-zero exit if `throwsOnFail`.
    static func run(_ cmd: String, _ args: [String], throwsOnFail: Bool = true) async throws -> Result {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Result, Error>) in
            let proc = makeProcess(cmd, args)
            let outPipe = Pipe(), errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            proc.terminationHandler = { p in
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let res = Result(exitCode: p.terminationStatus, stdout: out, stderr: err)
                if throwsOnFail && !res.ok {
                    cont.resume(throwing: ShellError.nonZeroExit(p.terminationStatus, stderr: err))
                } else {
                    cont.resume(returning: res)
                }
            }

            do { try proc.run() } catch { cont.resume(throwing: error) }
        }
    }

    /// Run and stream combined stdout+stderr line-by-line to `onLine`.
    /// Throws on non-zero exit.
    static func stream(
        _ cmd: String,
        _ args: [String],
        onLine: @escaping @Sendable (String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let proc = makeProcess(cmd, args)
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            var buffer = Data()
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { fh in
                let chunk = fh.availableData
                if chunk.isEmpty { return }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.subdata(in: 0..<nl)
                    buffer.removeSubrange(0...nl)
                    if let line = String(data: lineData, encoding: .utf8) {
                        onLine(line)
                    }
                }
            }

            proc.terminationHandler = { p in
                handle.readabilityHandler = nil
                if !buffer.isEmpty, let tail = String(data: buffer, encoding: .utf8) {
                    onLine(tail)
                }
                if p.terminationStatus == 0 {
                    cont.resume()
                } else {
                    cont.resume(throwing: ShellError.nonZeroExit(p.terminationStatus, stderr: ""))
                }
            }

            do { try proc.run() } catch { cont.resume(throwing: error) }
        }
    }

    /// Returns true if the named tool is resolvable on the user's shell PATH.
    static func hasTool(_ name: String) async -> Bool {
        (try? await run("command", ["-v", name], throwsOnFail: false))?.ok == true
    }
}
