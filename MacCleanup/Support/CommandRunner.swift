import Foundation

/// Runs a command-line tool and captures its output, with a timeout.
///
/// Only used for tools whose own cleanup logic can't be reproduced safely by
/// deleting files (Docker). Arguments are passed as an array, never through a shell.
enum CommandRunner {
    struct Output: Sendable {
        let status: Int32
        let standardOutput: String
        let standardError: String
    }

    enum Failure: Error, LocalizedError {
        case couldNotLaunch(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .couldNotLaunch(let reason): return "The command couldn't be started: \(reason)"
            case .timedOut: return "The command took too long and was stopped."
            }
        }
    }

    static func run(_ executable: URL, arguments: [String], timeout: TimeInterval = 30) throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        // Drain both pipes while the process runs so a chatty tool can't fill a
        // pipe buffer and deadlock.
        let outBuffer = LockedBuffer()
        let errBuffer = LockedBuffer()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            outBuffer.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            errBuffer.append(handle.availableData)
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw Failure.couldNotLaunch(error.localizedDescription)
        }

        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            _ = finished.wait(timeout: .now() + 5)
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        outBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
        errBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())

        if timedOut { throw Failure.timedOut }

        return Output(
            status: process.terminationStatus,
            standardOutput: String(decoding: outBuffer.data, as: UTF8.self),
            standardError: String(decoding: errBuffer.data, as: UTF8.self)
        )
    }

    private final class LockedBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()

        var data: Data {
            lock.lock(); defer { lock.unlock() }
            return storage
        }

        func append(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock(); defer { lock.unlock() }
            storage.append(chunk)
        }
    }
}
