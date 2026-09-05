import Foundation
import Darwin

enum ConsoleOutput {
    static let displayLimit = 128 * 1_024
    private static let escapes = try! NSRegularExpression(
        pattern: "\u{001B}(?:\\[[0-?]*[ -/]*[@-~]|\\][^\u{0007}]*(?:\u{0007}|\u{001B}\\\\))"
    )

    static func clean(_ value: String) -> String {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return escapes.stringByReplacingMatches(in: value, range: range, withTemplate: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isDiagnostic(_ line: String) -> Bool {
        let value = line.lowercased()
        return value.contains("failed to ") || value.contains("could not ")
            || value.contains("error:") || value.contains("permission denied")
            || value.contains("operation not permitted")
    }

    static func display(stdout: Data, stderr: Data, truncated: Bool) -> String {
        let omitted = truncated || stdout.count > displayLimit || stderr.count > displayLimit
        return [omitted ? "Earlier activity omitted to limit memory use. Operation records remain in History." : "",
                clean(String(decoding: stdout.suffix(displayLimit), as: UTF8.self)),
                clean(String(decoding: stderr.suffix(displayLimit), as: UTF8.self))]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private struct ByteTail {
    let limit: Int
    private var chunks: [Data] = []
    private(set) var count = 0
    private(set) var truncated = false

    mutating func append(_ data: Data) {
        guard !data.isEmpty else { return }
        if data.count >= limit {
            truncated = truncated || count + data.count > limit
            chunks = [Data(data.suffix(limit))]
            count = limit
            return
        }
        chunks.append(data)
        count += data.count
        while count > limit {
            truncated = true
            let discarded = min(count - limit, chunks[0].count)
            if discarded == chunks[0].count {
                chunks.removeFirst()
            } else {
                chunks[0] = Data(chunks[0].dropFirst(discarded))
            }
            count -= discarded
        }
    }

    var data: Data {
        var result = Data()
        result.reserveCapacity(count)
        for chunk in chunks { result.append(chunk) }
        return result
    }
}

private struct DiagnosticCapture {
    private var pending = Data()
    private(set) var first: String?

    mutating func append(_ data: Data) {
        guard first == nil else { return }
        for part in data.split(separator: 10, omittingEmptySubsequences: false).enumerated() {
            if part.offset > 0 {
                inspect()
                pending.removeAll(keepingCapacity: true)
            }
            guard first == nil else { return }
            pending.append(contentsOf: part.element.prefix(max(0, 4_096 - pending.count)))
        }
    }

    mutating func inspect() {
        guard first == nil else { return }
        let line = ConsoleOutput.clean(String(decoding: pending, as: UTF8.self))
        if ConsoleOutput.isDiagnostic(line) { first = String(line.prefix(500)) }
    }
}

struct ProcessOutputSnapshot {
    let stdout: Data
    let stderr: Data
    let truncated: Bool
    let error: String?
    let diagnostic: String?
}

// Readers run concurrently; only this object owns their buffers and update gate.
final class ProcessOutputCapture: @unchecked Sendable {
    static let textLimit = ConsoleOutput.displayLimit
    static let jsonLimit = 32 * 1_024 * 1_024
    private let lock = NSLock()
    private let format: MoleOutputFormat
    private let maximumJSONBytes: Int
    private var textOutput = ByteTail(limit: ProcessOutputCapture.textLimit)
    private var errors = ByteTail(limit: ProcessOutputCapture.textLimit)
    private var jsonOutput = Data()
    private var outputDiagnostic = DiagnosticCapture()
    private var errorDiagnostic = DiagnosticCapture()
    private var outputError: String?
    private var updatePending = false
    private var displayEnabled: Bool

    init(format: MoleOutputFormat, displayEnabled: Bool, jsonLimit: Int = ProcessOutputCapture.jsonLimit) {
        self.format = format
        self.displayEnabled = displayEnabled
        self.maximumJSONBytes = jsonLimit
    }

    // True schedules one coalesced UI update, regardless of writer throughput.
    func append(_ data: Data, isError: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isError {
            errors.append(data)
            errorDiagnostic.append(data)
        } else if format == .json {
            if outputError == nil {
                if data.count <= maximumJSONBytes - jsonOutput.count {
                    jsonOutput.append(data)
                } else {
                    outputError = "The result exceeded the memory limit. Use a narrower scan; review History before retrying a completed action."
                }
            }
        } else {
            textOutput.append(data)
            outputDiagnostic.append(data)
        }
        guard displayEnabled, !updatePending else { return false }
        updatePending = true
        return true
    }

    func recordReadError(_ error: Error) {
        lock.lock()
        if outputError == nil { outputError = "Could not read engine output: \(error.localizedDescription)" }
        lock.unlock()
    }

    func setDisplayEnabled(_ enabled: Bool) {
        lock.lock()
        displayEnabled = enabled
        lock.unlock()
    }

    func snapshot(consumingUpdate: Bool = false, finishing: Bool = false) -> ProcessOutputSnapshot {
        lock.lock()
        defer { lock.unlock() }
        if consumingUpdate { updatePending = false }
        if finishing {
            outputDiagnostic.inspect()
            errorDiagnostic.inspect()
        }
        return ProcessOutputSnapshot(
            stdout: format == .json
                ? (consumingUpdate ? Data(jsonOutput.suffix(Self.textLimit)) : jsonOutput)
                : textOutput.data,
            stderr: errors.data,
            truncated: textOutput.truncated || errors.truncated || (consumingUpdate && jsonOutput.count > Self.textLimit),
            error: outputError,
            diagnostic: errorDiagnostic.first ?? outputDiagnostic.first
        )
    }
}

// Read the bytes that are ready, rather than waiting to fill a Foundation
// read(upToCount:) request. Small progress messages reach the UI immediately.
func readProcessPipe(_ handle: FileHandle, receive: (Data) -> Void) throws {
    defer { try? handle.close() }
    let capacity = 8_192
    var buffer = [UInt8](repeating: 0, count: capacity)
    while true {
        let count = buffer.withUnsafeMutableBytes { bytes in
            Darwin.read(handle.fileDescriptor, bytes.baseAddress, capacity)
        }
        if count == 0 { return }
        if count < 0 {
            if errno == EINTR { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        receive(Data(buffer.prefix(count)))
    }
}

func engineProcessGroup(_ process: Process) -> pid_t? {
    let pid = process.processIdentifier
    return getpgid(pid) == pid && pid != getpgrp() ? pid : nil
}

func signalEngineProcess(_ process: Process, group: pid_t?, signal: Int32) {
    if let group {
        kill(-group, signal)
    } else if process.isRunning {
        kill(process.processIdentifier, signal)
    }
}
