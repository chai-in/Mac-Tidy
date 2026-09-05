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

    static func launchTarget(for invocation: MoleInvocation, enginePath: String, bundled: Bool) -> (url: URL, arguments: [String]) {
        let engine = URL(fileURLWithPath: enginePath)
        guard bundled else { return (engine, invocation.arguments) }
        switch invocation.arguments.first {
        case "status", "analyze":
            let name = invocation.arguments[0]
            return (engine.deletingLastPathComponent().appendingPathComponent("bin/\(name)-go"),
                    Array(invocation.arguments.dropFirst()))
        default:
            return (engine, invocation.arguments)
        }
    }
}

@MainActor
final class MoleActivity: ObservableObject {
    @Published var text = ""
}

@MainActor
final class MoleRunner: ObservableObject {
    @Published private(set) var executablePath: String?
    @Published private(set) var moleVersion = "Checking…"
    @Published private(set) var isRunning = false
    @Published private(set) var activeLabel: String?
    // Log changes only invalidate the activity panel, not every catalog view.
    let activityState = MoleActivity()
    private(set) var activity: String {
        get { activityState.text }
        set { activityState.text = newValue }
    }
    @Published private(set) var showsActivity = false
    @Published private(set) var lastExitCode: Int32?
    @Published private(set) var lastOutputError: String?
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
    private var historyData = Data()
    @Published var presentedError: String?

    private var currentProcess: Process?
    private var currentProcessGroup: pid_t?
    private var currentRunID: UUID?
    private var currentCapture: ProcessOutputCapture?
    private var streamsActivity = false
    private var statusStream: MoleStatusStream?
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
        runCapture(MoleCommands.version, recordActivity: false) { [weak self] result in
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
        runCapture(MoleCommands.statusJSON, recordActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode(StatusSnapshot.self, from: result.standardOutputData, description: "system health") {
                self.status = $0
            }
        }
    }

    func monitorStatus() async {
        guard !Task.isCancelled, !isRunning, let executablePath else { return }
        let stream = MoleStatusStream()
        statusStream?.cancel()
        statusStream = stream
        defer {
            stream.cancel()
            if statusStream === stream { statusStream = nil }
        }
        let invocation = MoleCommands.statusWatch
        let target = MoleExecutableLocator.launchTarget(for: invocation, enginePath: executablePath, bundled: usesBundledEngine)
        do {
            for try await data in stream.start(url: target.url, arguments: target.arguments, environment: Self.commandEnvironment(invocation: invocation)) {
                guard !Task.isCancelled, !isRunning, statusStream === stream else { break }
                let snapshot = try Self.decoder.decode(StatusSnapshot.self, from: data)
                if let error = snapshot.collectionError, !error.isEmpty {
                    throw StatusStreamError.invalid(error)
                }
                // The first watch record omits battery and hardware enrichment.
                // Keep the last complete snapshot until the immediate full one.
                guard snapshot.hardware?.totalRam?.isEmpty == false else { continue }
                status = snapshot
            }
        } catch {
            if !Task.isCancelled && !isRunning {
                presentedError = "Live system-health refresh failed: \(error.localizedDescription)"
            }
        }
    }

    func stopStatusMonitoring() {
        statusStream?.cancel()
        statusStream = nil
    }

    func refreshInstalledApps(completion: (([InstalledApplication]) -> Void)? = nil) {
        runCapture(MoleCommands.uninstallList, recordActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode([InstalledApplication].self, from: result.standardOutputData, description: "application inventory") {
                self.installedApps = $0
                completion?($0)
            }
        }
    }

    func analyze(path: String?) {
        runCapture(MoleCommands.analyzeJSON(path: path), recordActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode(DiskAnalysis.self, from: result.standardOutputData, description: "storage analysis") {
                self.diskAnalysis = $0
            }
        }
    }

    func moveAnalyzedItemsToTrash(paths: [String], completion: ((Bool) -> Void)? = nil) {
        runCapture(MoleCommands.moveToTrash(paths: paths)) { [weak self] result in
            guard let self else { return }
            if result.outputError == nil && !result.standardOutputData.isEmpty {
                self.decode([TrashResult].self, from: result.standardOutputData, description: "Trash results") {
                    self.trashResults = $0
                }
            }
            completion?(result.succeeded)
        }
    }

    func refreshInstallerCandidates(debug: Bool, completion: (([InstallerCandidate]) -> Void)? = nil) {
        runCapture(MoleCommands.installersList(debug: debug), recordActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode([InstallerCandidate].self, from: result.standardOutputData, description: "installer inventory") {
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
        runCapture(MoleCommands.purgeList(includeEmpty: includeEmpty, debug: debug), recordActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode([PurgeCandidate].self, from: result.standardOutputData, description: "project artifact inventory") {
                self.purgeCandidates = $0
                completion?($0)
            }
        }
    }

    func whitelistCatalog(for mode: WhitelistMode) -> WhitelistCatalog? {
        mode == .clean ? cleanWhitelistCatalog : optimizeWhitelistCatalog
    }

    func refreshWhitelist(_ mode: WhitelistMode) {
        runCapture(MoleCommands.whitelistList(mode), recordActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode(WhitelistCatalog.self, from: result.standardOutputData, description: "protection settings") { catalog in
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
        runCapture(MoleCommands.purgePathsList, recordActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode(PurgePathsCatalog.self, from: result.standardOutputData, description: "project scan paths") {
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
        runCapture(MoleCommands.touchIDStatus, recordActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode(TouchIDStatus.self, from: result.standardOutputData, description: "Touch ID status") {
                self.touchIDStatus = $0
            }
        }
    }

    func refreshHistory(limit: Int) {
        runCapture(MoleCommands.history(limit: limit), recordActivity: false) { [weak self] result in
            guard let self, result.succeeded else { return }
            self.decode(HistoryReport.self, from: result.standardOutputData, description: "activity history") {
                self.historyData = result.standardOutputData
                self.history = $0
            }
        }
    }

    func runCapture(
        _ invocation: MoleInvocation,
        recordActivity: Bool = true,
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
        stopStatusMonitoring()

        let process = Process()
        let standardOutputPipe = Pipe()
        let standardErrorPipe = Pipe()
        let target = MoleExecutableLocator.launchTarget(for: invocation, enginePath: executablePath, bundled: usesBundledEngine)
        process.executableURL = target.url
        process.arguments = target.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = standardOutputPipe
        process.standardError = standardErrorPipe
        process.environment = Self.commandEnvironment(invocation: invocation)

        let runID = UUID()
        currentRunID = runID
        let capture = ProcessOutputCapture(format: invocation.outputFormat, displayEnabled: recordActivity && showsActivity)
        currentCapture = capture
        streamsActivity = recordActivity
        cancelRequested = false
        activeLabel = invocation.label
        isRunning = true
        if recordActivity {
            activity = ""
            lastExitCode = nil
            lastOutputError = nil
        }

        do {
            try process.run()
            currentProcess = process
            currentProcessGroup = engineProcessGroup(process)
            try? standardOutputPipe.fileHandleForWriting.close()
            try? standardErrorPipe.fileHandleForWriting.close()
        } catch {
            currentProcess = nil
            currentProcessGroup = nil
            currentRunID = nil
            currentCapture = nil
            isRunning = false
            activeLabel = nil
            presentedError = "Could not start bundled Mole engine: \(error.localizedDescription)"
            return
        }

        let readers = DispatchGroup()
        let readerQueue = DispatchQueue.global(qos: .userInitiated)

        func consume(_ handle: FileHandle, isError: Bool) {
            readers.enter()
            readerQueue.async { [weak self] in
                defer { readers.leave() }
                do {
                    try readProcessPipe(handle) { chunk in
                        guard capture.append(chunk, isError: isError) else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            guard let self, self.currentRunID == runID else { return }
                            let snapshot = capture.snapshot(consumingUpdate: true)
                            if self.showsActivity {
                                self.activity = ConsoleOutput.display(stdout: snapshot.stdout, stderr: snapshot.stderr, truncated: snapshot.truncated)
                            }
                        }
                    }
                } catch {
                    capture.recordReadError(error)
                }
            }
        }

        consume(standardOutputPipe.fileHandleForReading, isError: false)
        consume(standardErrorPipe.fileHandleForReading, isError: true)

        readerQueue.async { [weak self] in
            process.waitUntilExit()
            readers.wait()
            let snapshot = capture.snapshot(finishing: true)
            let exitCode = process.terminationStatus

            DispatchQueue.main.async {
                guard let self, self.currentRunID == runID else { return }
                let wasCancelled = self.cancelRequested
                let result = CommandResult(
                    invocation: invocation,
                    standardOutputData: snapshot.stdout,
                    standardErrorData: snapshot.stderr,
                    exitCode: exitCode,
                    cancelled: wasCancelled,
                    outputTruncated: snapshot.truncated,
                    outputError: snapshot.error,
                    diagnostic: snapshot.diagnostic
                )

                self.currentProcess = nil
                self.currentProcessGroup = nil
                self.currentRunID = nil
                self.currentCapture = nil
                self.cancelRequested = false
                self.activeLabel = nil
                self.isRunning = false
                if recordActivity || !result.succeeded {
                    self.lastExitCode = exitCode
                    self.lastOutputError = result.outputError
                }

                if recordActivity || !result.succeeded {
                    self.activity = wasCancelled
                        ? [result.displayOutput, "Stopped. Changes already completed are not undone."].filter { !$0.isEmpty }.joined(separator: "\n\n")
                        : (result.displayOutput.isEmpty ? "Finished successfully." : result.displayOutput)
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
        signalEngineProcess(process, group: currentProcessGroup, signal: signal)
    }

    func toggleActivity() {
        showsActivity.toggle()
        currentCapture?.setDisplayEnabled(showsActivity && streamsActivity)
        if showsActivity, streamsActivity, let snapshot = currentCapture?.snapshot(consumingUpdate: true) {
            activity = ConsoleOutput.display(stdout: snapshot.stdout, stderr: snapshot.stderr, truncated: snapshot.truncated)
        }
    }

    func copyActivity() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(activity, forType: .string)
    }

    func exportHistory() {
        guard !historyData.isEmpty else {
            presentedError = "Load history before exporting it."
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "mole-history.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try historyData.write(to: url, options: .atomic)
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
        from data: Data,
        description: String,
        assign: (Value) -> Void
    ) {
        do {
            assign(try Self.decoder.decode(type, from: data))
        } catch {
            presentedError = "Mole returned \(description) this app could not read: \(error.localizedDescription)"
        }
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
        if let error = result.outputError { return "\(result.invocation.label) failed: \(error)" }
        if let diagnostic = result.diagnostic { return "\(result.invocation.label) failed: \(diagnostic)" }
        let errorLines = result.standardError
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let outputLines = result.standardOutput
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        // Engine task diagnostics can be written to stdout after the heading.
        // Keep the full output in Activity, and put the actual cause in the alert.
        let diagnostic = (errorLines + outputLines).first { line in
            ConsoleOutput.isDiagnostic(line)
        }
        if let detail = diagnostic ?? errorLines.first {
            return "\(result.invocation.label) failed: \(detail.prefix(500))"
        }
        return "\(result.invocation.label) failed with exit code \(result.exitCode). See Activity for details."
    }

}
