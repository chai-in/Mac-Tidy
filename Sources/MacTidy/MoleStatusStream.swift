import Darwin
import Foundation

enum StatusStreamError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct JSONLineBuffer {
    let maximumBytes: Int
    private var pending = Data()

    init(maximumBytes: Int = 1_024 * 1_024) { self.maximumBytes = maximumBytes }

    mutating func append(_ data: Data) throws -> [Data] {
        var frames: [Data] = []
        for part in data.split(separator: 10, omittingEmptySubsequences: false).enumerated() {
            if part.offset > 0 {
                if !pending.isEmpty { frames.append(pending) }
                pending = Data()
            }
            guard part.element.count <= maximumBytes - pending.count else {
                throw StatusStreamError.invalid("A system-health response exceeded the memory limit.")
            }
            pending.append(contentsOf: part.element)
        }
        return frames
    }
}

// A foreground-only consumer of Mole's existing NDJSON watch protocol.
// Keep at most one unread snapshot; newer telemetry replaces obsolete samples.
final class MoleStatusStream: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var processGroup: pid_t?
    private var cancelled = false
    private var finished = false
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?

    func start(url: URL, arguments: [String], environment: [String: String]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in self?.cancel() }
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = url
            process.arguments = arguments
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = errors
            do {
                try process.run()
                processGroup = engineProcessGroup(process)
                try? output.fileHandleForWriting.close()
                try? errors.fileHandleForWriting.close()
            } catch {
                lock.lock()
                finished = true
                lock.unlock()
                continuation.finish(throwing: error)
                return
            }

            let readers = DispatchGroup()
            let queue = DispatchQueue.global(qos: .utility)
            let errorCapture = ProcessOutputCapture(format: .text, displayEnabled: false)
            readers.enter()
            queue.async {
                defer { readers.leave() }
                var buffer = JSONLineBuffer()
                do {
                    try readProcessPipe(output.fileHandleForReading) { chunk in
                        do {
                            for frame in try buffer.append(chunk) { continuation.yield(frame) }
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            readers.enter()
            queue.async {
                defer { readers.leave() }
                do {
                    try readProcessPipe(errors.fileHandleForReading) { chunk in
                        _ = errorCapture.append(chunk, isError: true)
                    }
                } catch {
                    errorCapture.recordReadError(error)
                }
            }
            queue.async { [self] in
                process.waitUntilExit()
                readers.wait()
                lock.lock()
                finished = true
                let wasCancelled = cancelled
                lock.unlock()
                let snapshot = errorCapture.snapshot(finishing: true)
                if !wasCancelled && (process.terminationStatus != 0 || snapshot.error != nil) {
                    let detail = snapshot.error ?? snapshot.diagnostic
                        ?? ConsoleOutput.clean(String(decoding: snapshot.stderr, as: UTF8.self))
                    continuation.finish(throwing: StatusStreamError.invalid(
                        detail.isEmpty ? "System-health refresh exited with code \(process.terminationStatus)." : String(detail.prefix(500))
                    ))
                } else if !wasCancelled {
                    continuation.finish(throwing: StatusStreamError.invalid("System-health refresh stopped unexpectedly. Turn automatic refresh off and on to retry."))
                } else {
                    continuation.finish()
                }
            }
        }
    }

    func cancel() {
        lock.lock()
        guard !cancelled && !finished else { lock.unlock(); return }
        cancelled = true
        let group = processGroup
        let continuation = continuation
        lock.unlock()
        signalEngineProcess(process, group: group, signal: SIGTERM)
        continuation?.finish()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            lock.lock()
            let stillDraining = !finished
            lock.unlock()
            if stillDraining { signalEngineProcess(process, group: group, signal: SIGKILL) }
        }
    }
}
