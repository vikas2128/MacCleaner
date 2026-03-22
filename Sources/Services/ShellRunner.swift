import Foundation

/// Executes shell commands safely and returns their output.
/// Used exclusively for read-only queries (tmutil listlocalsnapshots)
/// and explicitly user-approved deletion commands (tmutil deletelocalsnapshots).
struct ShellRunner {
    /// Run a command, return (output, success)
    @discardableResult
    static func run(_ command: String, args: [String]) -> (output: String, success: Bool) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (output, process.terminationStatus == 0)
        } catch {
            return ("Error: \(error.localizedDescription)", false)
        }
    }

    /// List all local Time Machine snapshots on the boot volume.
    /// Returns an array of snapshot date strings like ["2025-03-20-123456", ...]
    static func listLocalSnapshots() -> [String] {
        let (output, success) = run("/usr/bin/tmutil", args: ["listlocalsnapshotdates", "/"])
        guard success else { return [] }
        return output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("-") && $0.count > 10 }  // date format guard
    }

    /// Delete a single local snapshot by date string.
    /// Requires the process to be running as root (or admin via sudo outside the app).
    @discardableResult
    static func deleteLocalSnapshot(_ date: String) -> Bool {
        // ✅ Validate input — only allow date-like strings to prevent injection
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard date.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let (_, success) = run("/usr/bin/tmutil", args: ["deletelocalsnapshots", date])
        return success
    }
}
