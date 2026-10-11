import Foundation

/// Talks to the `docker` command-line tool to estimate and reclaim unused resources.
///
/// Docker's own `prune` commands are used rather than deleting files, because
/// Docker's data lives inside a virtual disk the app can't safely edit directly.
/// Only unused objects are pruned: stopped containers, dangling images and
/// build cache. Volumes (which can hold databases) are never touched.
enum DockerService {
    enum DockerError: Error, LocalizedError {
        case notInstalled
        case notRunning
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Docker isn't installed."
            case .notRunning: return "Docker isn't running. Start Docker Desktop and scan again."
            case .commandFailed(let message): return message
            }
        }
    }

    struct Estimate: Sendable {
        struct Part: Sendable {
            let name: String
            let bytes: Int64
            let objectCount: Int
        }

        let parts: [Part]
        var totalBytes: Int64 { parts.reduce(0) { $0 + $1.bytes } }
        var objectCount: Int { parts.reduce(0) { $0 + $1.objectCount } }
    }

    struct PruneResult: Sendable {
        let bytesReclaimed: Int64
    }

    // MARK: - Locating the CLI

    /// GUI apps don't inherit the shell's PATH, so look in the usual places.
    static func locateCLI(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            homeDirectory.appendingPathComponent(".docker/bin/docker").path,
            homeDirectory.appendingPathComponent(".rd/bin/docker").path, // Rancher Desktop
        ]
        return candidates
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Estimate

    static func estimate() throws -> Estimate {
        guard let docker = locateCLI() else { throw DockerError.notInstalled }

        let df = try run(docker, ["system", "df", "--format", "{{json .}}"])
        let rows = df.split(whereSeparator: \.isNewline).compactMap { line -> DiskUsageRow? in
            try? JSONDecoder().decode(DiskUsageRow.self, from: Data(line.utf8))
        }

        var parts: [Estimate.Part] = []

        if let containers = rows.first(where: { $0.type == "Containers" }) {
            let unused = max(0, (Int(containers.totalCount) ?? 0) - (Int(containers.active) ?? 0))
            parts.append(.init(
                name: "Stopped containers",
                bytes: parseSize(containers.reclaimable) ?? 0,
                objectCount: unused
            ))
        }

        // Only dangling images are pruned, so count exactly those rather than
        // Docker's larger "reclaimable" figure for all unused images.
        let dangling = try run(docker, ["images", "--filter", "dangling=true", "--format", "{{.Size}}"])
        let danglingSizes = dangling.split(whereSeparator: \.isNewline).compactMap { parseSize(String($0)) }
        parts.append(.init(
            name: "Dangling images",
            bytes: danglingSizes.reduce(0, +),
            objectCount: danglingSizes.count
        ))

        if let cache = rows.first(where: { $0.type == "Build Cache" }) {
            let unused = max(0, (Int(cache.totalCount) ?? 0) - (Int(cache.active) ?? 0))
            parts.append(.init(
                name: "Build cache",
                bytes: parseSize(cache.reclaimable) ?? 0,
                objectCount: unused
            ))
        }

        return Estimate(parts: parts.filter { $0.bytes > 0 || $0.objectCount > 0 })
    }

    // MARK: - Prune

    /// Removes stopped containers, dangling images and unused build cache.
    static func prune() throws -> PruneResult {
        guard let docker = locateCLI() else { throw DockerError.notInstalled }

        var reclaimed: Int64 = 0
        let commands = [
            ["container", "prune", "--force"],
            ["image", "prune", "--force"],
            ["builder", "prune", "--force"],
        ]
        for arguments in commands {
            let output = try run(docker, arguments)
            reclaimed += reclaimedBytes(in: output) ?? 0
        }
        return PruneResult(bytesReclaimed: reclaimed)
    }

    // MARK: - Parsing

    /// Parses Docker sizes such as "1.2GB", "45.3kB", "512 MB" or "3.2GB (45%)".
    static func parseSize(_ text: String) -> Int64? {
        let trimmed = text.split(separator: "(").first.map(String.init) ?? text
        let cleaned = trimmed.trimmingCharacters(in: .whitespaces)

        let numberPart = cleaned.prefix { $0.isNumber || $0 == "." }
        let unitPart = cleaned.dropFirst(numberPart.count)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        guard let value = Double(numberPart) else { return nil }

        let multiplier: Double
        switch unitPart {
        case "", "b": multiplier = 1
        case "kb": multiplier = 1_000
        case "mb": multiplier = 1_000_000
        case "gb": multiplier = 1_000_000_000
        case "tb": multiplier = 1_000_000_000_000
        case "pb": multiplier = 1_000_000_000_000_000
        case "kib": multiplier = 1_024
        case "mib": multiplier = 1_048_576
        case "gib": multiplier = 1_073_741_824
        case "tib": multiplier = 1_099_511_627_776
        default: return nil
        }
        return Int64(value * multiplier)
    }

    /// Reads the figure from a "Total reclaimed space: 1.2GB" line.
    static func reclaimedBytes(in output: String) -> Int64? {
        let marker = "Total reclaimed space:"
        for line in output.split(whereSeparator: \.isNewline) {
            guard let range = line.range(of: marker) else { continue }
            return parseSize(String(line[range.upperBound...]))
        }
        return nil
    }

    // MARK: - Private

    private struct DiskUsageRow: Decodable {
        let type: String
        let totalCount: String
        let active: String
        let reclaimable: String

        enum CodingKeys: String, CodingKey {
            case type = "Type"
            case totalCount = "TotalCount"
            case active = "Active"
            case reclaimable = "Reclaimable"
        }
    }

    private static func run(_ docker: URL, _ arguments: [String]) throws -> String {
        let output: CommandRunner.Output
        do {
            output = try CommandRunner.run(docker, arguments: arguments, timeout: 120)
        } catch {
            throw DockerError.commandFailed(error.localizedDescription)
        }
        guard output.status == 0 else {
            let message = output.standardError.lowercased()
            if message.contains("cannot connect") || message.contains("is the docker daemon running") {
                throw DockerError.notRunning
            }
            let detail = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DockerError.commandFailed(detail.isEmpty ? "Docker reported an error." : detail)
        }
        return output.standardOutput
    }
}
