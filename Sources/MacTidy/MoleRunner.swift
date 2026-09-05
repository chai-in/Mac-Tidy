import AppKit
import Combine
import Darwin
import Foundation
import UniformTypeIdentifiers

enum MoleExecutableLocator {
    static func candidatePaths(
        resourceURL: URL?,
        environment: [String: String],
        homePath: String,
        pathVariable: String,
        allowDevelopmentFallback: Bool = true
    ) -> [String] {
        var paths: [String] = []
        if let resourceURL {
            paths.append(resourceURL.appendingPathComponent("Mole/mole").path)
        }
        guard allowDevelopmentFallback else { return paths }

        if let override = environment["MAC_TIDY_EXECUTABLE"], !override.isEmpty {
            paths.append(override)
        }
        paths += [
            "/opt/homebrew/bin/mo",
            "/usr/local/bin/mo",
            URL(fileURLWithPath: homePath).appendingPathComponent(".local/bin/mo").path
        ]
        paths += pathVariable
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("mo").path }

        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    static func find(
        resourceURL: URL? = Bundle.main.resourceURL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homePath: String = FileManager.default.homeDirectoryForCurrentUser.path,
        allowDevelopmentFallback: Bool? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        let fallbackAllowed = allowDevelopmentFallback
            ?? (Bundle.main.bundleURL.pathExtension.lowercased() != "app")
        return candidatePaths(
            resourceURL: resourceURL,
            environment: environment,
            homePath: homePath,
            pathVariable: environment["PATH", default: ""],
            allowDevelopmentFallback: fallbackAllowed
        ).first { fileManager.isExecutableFile(atPath: $0) }
    }
}

private final class LockedProcessCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var standardOutput = Data()
    private var standardError = Data()

    func append(_ data: Data, isError: Bool) {
        lock.lock()
        if isError {
            standardError.append(data)
        } else {
            standardOutput.append(data)
        }
        lock.unlock()
    }

    func snapshot() -> (Data, Data) {
        lock.lock()
        defer { lock.unlock() }
        return (standardOutput, standardError)
    }
}

@MainActor
final class MoleRunner: ObservableObject {
    @Published private(set) var executablePath: String?
    @Published private(set) var moleVersion = "Checking…"
    @Published private(set) var isRunning = false
    @Published private(set) var activeLabel: String?
    @Published private(set) var activity = ""
    @Published private(set) var showsActivity = false
    @Published private(set) var lastExitCode: Int32?
    @Published private(set) var status: StatusSnapshot?
    @Published private(set) var installedApps: [InstalledApplication] = []
    @Published private(set) var diskAnalysis: DiskAnalysis?
    @Published private(set) var installerCandidates: [InstallerCandidate] = []
    @Published private(set) var purgeCandidates: [PurgeCandidate] = []
    @Published private(set) var cleanWhitelistCatalog: WhitelistCatalog?
    @Published private(set) var optimizeWhitelistCatalog: WhitelistCatalog?
    @Published private(set) var purgePathsCatalog: PurgePathsCatalog?
    @Published private(set) var trashResults: [TrashResult] = []
    @Published private(set) var touchIDStatus: TouchIDStatus?
    @Published private(set) var history: HistoryReport?
    @Published private(set) var historyJSON = ""
    @Published var presentedError: String?

    private var currentProcess: Process?
    private var currentProcessGroup: pid_t?
    private var currentRunID: UUID?
    @Published private(set) var cancelRequested = false
    private var didBootstrap = false

    init(executablePath: String? = MoleExecutableLocator.find()) {
        self.executablePath = executablePath
        if executablePath == nil { moleVersion = "Unavailable" }
    }

    var isAvailable: Bool { executablePath != nil }

    var usesBundledEngine: Bool {
        guard let executablePath, let resources = Bundle.main.resourceURL else { return false }
        return executablePath.hasPrefix(resources.appendingPathComponent("Mole").path + "/")
    }

    var bundledLicenseURL: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent("Mole/LICENSE")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        guard isAvailable else { return }
        runCapture(MoleCommands.version, showActivity: false) { [weak self] result in
            guard let self else { return }
            guard result.succeeded else {
                self.executablePath = nil
                self.moleVersion = "Unavailable"
                return
            }
            let version = Self.parseVersion(result.standardOutput)
            self.moleVersion = version
            if self.usesBundledEngine && version != AppMetadata.bundledMoleVersion {
                self.executablePath = nil
                self.presentedError = "Bundled Mole engine version mismatch. Reinstall Mac Tidy."
                return
            }
            self.refreshStatus()
        }
    }

    func refreshStatus() {
        runCapture(MoleCommands.statusJSON, showActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode(StatusSnapshot.self, from: result.standardOutput, description: "system health") {
                self.status = $0
            }
        }
    }

    func refreshInstalledApps(completion: (([InstalledApplication]) -> Void)? = nil) {
        runCapture(MoleCommands.uninstallList, showActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode([InstalledApplication].self, from: result.standardOutput, description: "application inventory") {
                self.installedApps = $0
                completion?($0)
            }
        }
    }

    func analyze(path: String?) {
        runCapture(MoleCommands.analyzeJSON(path: path), showActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode(DiskAnalysis.self, from: result.standardOutput, description: "storage analysis") {
                self.diskAnalysis = $0
            }
        }
    }

    func moveAnalyzedItemsToTrash(paths: [String], completion: ((Bool) -> Void)? = nil) {
        runCapture(MoleCommands.moveToTrash(paths: paths)) { [weak self] result in
            guard let self else { return }
            if !result.standardOutput.isEmpty {
                self.decode([TrashResult].self, from: result.standardOutput, description: "Trash results") {
                    self.trashResults = $0
                }
            }
            completion?(result.succeeded)
        }
    }

    func refreshInstallerCandidates(debug: Bool, completion: (([InstallerCandidate]) -> Void)? = nil) {
        runCapture(MoleCommands.installersList(debug: debug), showActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode([InstallerCandidate].self, from: result.standardOutput, description: "installer inventory") {
                self.installerCandidates = $0
                completion?($0)
            }
        }
    }

    func refreshPurgeCandidates(
        includeEmpty: Bool,
        debug: Bool,
        completion: (([PurgeCandidate]) -> Void)? = nil
    ) {
        runCapture(MoleCommands.purgeList(includeEmpty: includeEmpty, debug: debug), showActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode([PurgeCandidate].self, from: result.standardOutput, description: "project artifact inventory") {
                self.purgeCandidates = $0
                completion?($0)
            }
        }
    }

    func whitelistCatalog(for mode: WhitelistMode) -> WhitelistCatalog? {
        mode == .clean ? cleanWhitelistCatalog : optimizeWhitelistCatalog
    }

    func refreshWhitelist(_ mode: WhitelistMode) {
        runCapture(MoleCommands.whitelistList(mode), showActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode(WhitelistCatalog.self, from: result.standardOutput, description: "protection settings") { catalog in
                if mode == .clean {
                    self.cleanWhitelistCatalog = catalog
                } else {
                    self.optimizeWhitelistCatalog = catalog
                }
            }
        }
    }

    func saveWhitelist(_ mode: WhitelistMode, patterns: [String], completion: ((Bool) -> Void)? = nil) {
        runCapture(MoleCommands.whitelistSave(mode, patterns: patterns)) { [weak self] result in
            guard let self else { return }
            if result.succeeded { self.refreshWhitelist(mode) }
            completion?(result.succeeded)
        }
    }

    func refreshPurgePaths() {
        runCapture(MoleCommands.purgePathsList, showActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode(PurgePathsCatalog.self, from: result.standardOutput, description: "project scan paths") {
                self.purgePathsCatalog = $0
            }
        }
    }

    func savePurgePaths(_ paths: [String], completion: ((Bool) -> Void)? = nil) {
        runCapture(MoleCommands.purgePathsSave(paths)) { [weak self] result in
            guard let self else { return }
            if result.succeeded { self.refreshPurgePaths() }
            completion?(result.succeeded)
        }
    }

    func refreshTouchIDStatus() {
        runCapture(MoleCommands.touchIDStatus, showActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode(TouchIDStatus.self, from: result.standardOutput, description: "Touch ID status") {
                self.touchIDStatus = $0
            }
        }
    }

    func refreshHistory(limit: Int) {
        runCapture(MoleCommands.history(limit: limit), showActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode(HistoryReport.self, from: result.standardOutput, description: "activity history") {
                self.historyJSON = result.standardOutput
                self.history = $0
            }
        }
    }

    func runCapture(
        _ invocation: MoleInvocation,
        showActivity: Bool = true,
        completion: ((CommandResult) -> Void)? = nil
    ) {
        if invocation.risk.requiresNativeConfirmation && invocation.environment["MOLE_GUI_CONFIRMED"] != "1" {
            presentedError = "Action was not confirmed."
            return
        }
        guard !isRunning else {
            presentedError = "Wait for \(activeLabel ?? "current activity") to finish."
            return
        }
        guard let executablePath else {
            presentedError = "Bundled Mole engine is unavailable. Reinstall this app."
            return
        }

        let process = Process()
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = invocation.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe
        process.environment = Self.commandEnvironment(invocation: invocation)

        let runID = UUID()
        currentRunID = runID
        cancelRequested = false
        activeLabel = invocation.label
        isRunning = true
        if showActivity {
            activity = ""
            lastExitCode = nil
            showsActivity = true
        }

        do {
            try process.run()
            currentProcess = process
            let pid = process.processIdentifier
            currentProcessGroup = getpgid(pid) == pid && pid != getpgrp() ? pid : nil
            try? standardOutputPipe.fileHandleForWriting.close()
            try? standardErrorPipe.fileHandleForWriting.close()
        } catch {
            currentProcess = nil
            currentProcessGroup = nil
            currentRunID = nil
            isRunning = false
            activeLabel = nil
            presentedError = "Could not start bundled Mole engine: \(error.localizedDescription)"
            return
        }

        let capture = LockedProcessCapture()
        let readers = DispatchGroup()
        let readerQueue = DispatchQueue.global(qos: .userInitiated)

        func consume(_ handle: FileHandle, isError: Bool) {
            readers.enter()
            readerQueue.async { [weak self] in
                defer { readers.leave() }
                while true {
                    let chunk: Data
                    do {
                        guard let data = try handle.read(upToCount: 8_192), !data.isEmpty else { break }
                        chunk = data
                    } catch {
                        break
                    }
                    capture.append(chunk, isError: isError)
                    guard showActivity else { continue }
                    let text = String(decoding: chunk, as: UTF8.self)
                    DispatchQueue.main.async {
                        self?.appendActivity(text, runID: runID)
                    }
                }
            }
        }

        consume(standardOutputPipe.fileHandleForReading, isError: false)
        consume(standardErrorPipe.fileHandleForReading, isError: true)

        readerQueue.async { [weak self] in
            process.waitUntilExit()
            readers.wait()
            let (outputData, errorData) = capture.snapshot()
            let standardOutput = Self.cleanOutput(String(decoding: outputData, as: UTF8.self))
            let standardError = Self.cleanOutput(String(decoding: errorData, as: UTF8.self))
            let exitCode = process.terminationStatus

            DispatchQueue.main.async {
                guard let self, self.currentRunID == runID else { return }
                let wasCancelled = self.cancelRequested
                let result = CommandResult(
                    invocation: invocation,
                    standardOutput: standardOutput,
                    standardError: standardError,
                    exitCode: exitCode,
                    cancelled: wasCancelled
                )

                self.currentProcess = nil
                self.currentProcessGroup = nil
                self.currentRunID = nil
                self.cancelRequested = false
                self.activeLabel = nil
                self.isRunning = false
                if showActivity || !result.succeeded { self.lastExitCode = exitCode }

                if showActivity || !result.succeeded {
                    self.activity = wasCancelled
                        ? [result.displayOutput, "Stopped. Changes already completed are not undone."].filter { !$0.isEmpty }.joined(separator: "\n\n")
                        : (result.displayOutput.isEmpty ? "Finished successfully." : result.displayOutput)
                    self.showsActivity = true
                }
                if !result.succeeded && !wasCancelled {
                    self.presentedError = Self.failureMessage(for: result)
                }
                completion?(result)
            }
        }
    }

    func cancel() {
        guard let currentProcess, !cancelRequested else { return }
        cancelRequested = true
        activeLabel = "Stopping…"
        signalProcess(currentProcess, signal: SIGTERM)
        let runID = currentRunID
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak currentProcess] in
            guard let self, let currentProcess, self.currentRunID == runID else { return }
            self.signalProcess(currentProcess, signal: SIGKILL)
        }
    }

    private func signalProcess(_ process: Process, signal: Int32) {
        // Foundation launches a separate process group on macOS. Only signal
        // the group verified at launch. It may outlive its shell while children
        // retain the output pipes; keep Stop pending until those pipes close.
        if let group = currentProcessGroup {
            kill(-group, signal)
        } else if process.isRunning {
            kill(process.processIdentifier, signal)
        }
    }

    func toggleActivity() {
        showsActivity.toggle()
    }

    func clearActivity() {
        guard !isRunning else { return }
        activity = ""
        lastExitCode = nil
        showsActivity = false
    }

    func copyActivity() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(activity, forType: .string)
    }

    func exportHistory() {
        guard !historyJSON.isEmpty else {
            presentedError = "Load history before exporting it."
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mole-history.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(historyJSON.utf8).write(to: url, options: .atomic)
        } catch {
            presentedError = "Could not save history: \(error.localizedDescription)"
        }
    }

    func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openBundledLicense() {
        guard let bundledLicenseURL else {
            presentedError = "Bundled license file is unavailable."
            return
        }
        NSWorkspace.shared.open(bundledLicenseURL)
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from text: String,
        description: String,
        assign: (Value) -> Void
    ) {
        do {
            assign(try Self.decoder.decode(type, from: Data(text.utf8)))
        } catch {
            presentedError = "Mole returned \(description) this app could not read: \(error.localizedDescription)"
        }
    }

    private func appendActivity(_ value: String, runID: UUID) {
        guard currentRunID == runID else { return }
        activity += Self.cleanOutputChunk(value)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    nonisolated static func commandEnvironment(
        invocation: MoleInvocation,
        inherited: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        // Private bridge state belongs to this invocation, never the launcher.
        var environment = inherited.filter { !$0.key.hasPrefix("MOLE_GUI_") }
        environment.removeValue(forKey: "BASH_ENV")
        environment.removeValue(forKey: "ENV")
        let standardPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let currentPath = environment["PATH", default: ""]
        environment["PATH"] = currentPath.isEmpty ? standardPath : "\(standardPath):\(currentPath)"
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        for (key, value) in invocation.environment {
            environment[key] = value
        }
        environment["MOLE_GUI_MODE"] = "1"
        if !invocation.risk.requiresNativeConfirmation {
            environment.removeValue(forKey: "MOLE_GUI_CONFIRMED")
        }
        return environment
    }

    nonisolated static func parseVersion(_ output: String) -> String {
        for line in output.split(separator: "\n") {
            let text = String(line).trimmingCharacters(in: .whitespaces)
            if text.lowercased().hasPrefix("mole version ") {
                return String(text.dropFirst("Mole version ".count))
            }
        }
        return output.split(separator: "\n").first.map(String.init) ?? "Unknown"
    }

    nonisolated private static func failureMessage(for result: CommandResult) -> String {
        let detail = (result.standardError.isEmpty ? result.standardOutput : result.standardError)
            .split(separator: "\n")
            .first
            .map(String.init)
        if let detail, !detail.isEmpty {
            return "\(result.invocation.label) failed: \(detail)"
        }
        return "\(result.invocation.label) failed with exit code \(result.exitCode)."
    }

    nonisolated private static func cleanOutput(_ value: String) -> String {
        cleanOutputChunk(value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func cleanOutputChunk(_ value: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"\u{001B}(?:\[[0-?]*[ -/]*[@-~]|\][^\u{0007}]*(?:\u{0007}|\u{001B}\\))"#
        ) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: "")
            .replacingOccurrences(of: "\r", with: "")
    }
}
