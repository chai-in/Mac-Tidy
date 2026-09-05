import Foundation

enum AppMetadata {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    static let bundledMoleVersion = Bundle.main.object(forInfoDictionaryKey: "MoleEngineVersion") as? String ?? "1.53.0"
    static let bundledMoleCommit = Bundle.main.object(forInfoDictionaryKey: "MoleEngineCommit") as? String
        ?? "1b9023b5f151c2d963bbcb9cb658f4824137b8aa"
}

enum MoleRisk: Equatable {
    case readOnly
    case preview
    case configuration
    case recoverableMutation
    case destructiveMutation
    case privilegedMutation

    var requiresNativeConfirmation: Bool {
        switch self {
        case .recoverableMutation, .destructiveMutation, .privilegedMutation:
            true
        case .readOnly, .preview, .configuration:
            false
        }
    }
}

struct MoleInvocation: Equatable {
    let label: String
    let arguments: [String]
    let risk: MoleRisk
    let environment: [String: String]

    init(label: String, arguments: [String], risk: MoleRisk, environment: [String: String] = [:]) {
        self.label = label
        self.arguments = arguments
        self.risk = risk
        self.environment = environment
    }
}

enum WhitelistMode: String, CaseIterable, Identifiable {
    case clean
    case optimize

    var id: String { rawValue }
    var title: String { self == .clean ? "Cleanup Protections" : "Optimization Protections" }
}

enum MoleCommands {
    private static let confirmed = ["MOLE_GUI_CONFIRMED": "1"]

    static let version = MoleInvocation(
        label: "Check bundled engine",
        arguments: ["--version"],
        risk: .readOnly
    )

    static func clean(
        preview: Bool,
        externalPath: String?,
        debug: Bool,
        includeSystemCaches: Bool
    ) -> MoleInvocation {
        var arguments = ["clean"]
        if preview { arguments.append("--dry-run") }
        if let path = externalPath?.trimmedNil { arguments += ["--external", path] }
        if debug { arguments.append("--debug") }
        var environment = preview ? [:] : confirmed
        environment["MOLE_GUI_SYSTEM_CACHES"] = includeSystemCaches ? "include" : "skip"
        return MoleInvocation(
            label: preview ? "Preview cleanup" : "Clean storage",
            arguments: arguments,
            risk: preview ? .preview : .destructiveMutation,
            environment: environment
        )
    }

    static func whitelistList(_ mode: WhitelistMode) -> MoleInvocation {
        MoleInvocation(
            label: "Load \(mode.title.lowercased())",
            arguments: [mode.rawValue, "--gui-whitelist-list"],
            risk: .readOnly
        )
    }

    static func whitelistSave(_ mode: WhitelistMode, patterns: [String]) -> MoleInvocation {
        MoleInvocation(
            label: "Save \(mode.title.lowercased())",
            arguments: [mode.rawValue, "--gui-whitelist-save"] + patterns,
            risk: .configuration
        )
    }

    static let uninstallList = MoleInvocation(
        label: "Scan applications",
        arguments: ["uninstall", "--list"],
        risk: .readOnly
    )

    static func uninstall(paths: [String], preview: Bool, permanent: Bool, debug: Bool) -> MoleInvocation {
        var arguments = ["uninstall"]
        if preview { arguments.append("--dry-run") }
        if permanent { arguments.append("--permanent") }
        if debug { arguments.append("--debug") }
        arguments += paths.map { "--gui-path=\($0)" }
        return MoleInvocation(
            label: preview ? "Preview application removal" : "Uninstall applications",
            arguments: arguments,
            risk: preview ? .preview : (permanent ? .destructiveMutation : .recoverableMutation),
            environment: preview ? [:] : confirmed
        )
    }

    static func optimize(preview: Bool, debug: Bool) -> MoleInvocation {
        var arguments = ["optimize"]
        if preview { arguments.append("--dry-run") }
        if debug { arguments.append("--debug") }
        return MoleInvocation(
            label: preview ? "Preview optimization" : "Optimize macOS",
            arguments: arguments,
            risk: preview ? .preview : .privilegedMutation,
            environment: preview ? [:] : confirmed
        )
    }

    static func analyzeJSON(path: String?) -> MoleInvocation {
        var arguments = ["analyze", "--json"]
        if let path = path?.trimmedNil { arguments.append(path) }
        return MoleInvocation(label: "Analyze storage", arguments: arguments, risk: .readOnly)
    }

    static func moveToTrash(paths: [String]) -> MoleInvocation {
        MoleInvocation(
            label: "Move selected items to Trash",
            arguments: ["analyze", "--trash-json"] + paths,
            risk: .recoverableMutation,
            environment: confirmed
        )
    }

    static let statusJSON = MoleInvocation(
        label: "Refresh system health",
        arguments: ["status", "--json"],
        risk: .readOnly
    )

    static func history(limit: Int) -> MoleInvocation {
        MoleInvocation(
            label: "Load activity history",
            arguments: ["history", "--json", "--limit", "\(min(max(limit, 1), 200))"],
            risk: .readOnly
        )
    }

    static func purgeList(includeEmpty: Bool, debug: Bool) -> MoleInvocation {
        var arguments = ["purge", "--gui-list"]
        if includeEmpty { arguments.append("--include-empty") }
        if debug { arguments.append("--debug") }
        return MoleInvocation(label: "Scan project artifacts", arguments: arguments, risk: .readOnly)
    }

    static func purgeRemove(paths: [String], preview: Bool, includeEmpty: Bool, debug: Bool) -> MoleInvocation {
        var arguments = ["purge"]
        if preview { arguments.append("--dry-run") }
        if includeEmpty { arguments.append("--include-empty") }
        if debug { arguments.append("--debug") }
        arguments.append("--gui-remove")
        arguments += paths
        return MoleInvocation(
            label: preview ? "Preview project purge" : "Purge project artifacts",
            arguments: arguments,
            risk: preview ? .preview : .destructiveMutation,
            environment: preview ? [:] : confirmed
        )
    }

    static let purgePathsList = MoleInvocation(
        label: "Load project scan paths",
        arguments: ["purge", "--gui-paths-list"],
        risk: .readOnly
    )

    static func purgePathsSave(_ paths: [String]) -> MoleInvocation {
        MoleInvocation(
            label: "Save project scan paths",
            arguments: ["purge", "--gui-paths-save"] + paths,
            risk: .configuration
        )
    }

    static func installersList(debug: Bool) -> MoleInvocation {
        var arguments = ["installer", "--gui-list"]
        if debug { arguments.append("--debug") }
        return MoleInvocation(label: "Scan installer files", arguments: arguments, risk: .readOnly)
    }

    static func installersRemove(paths: [String], preview: Bool, debug: Bool) -> MoleInvocation {
        var arguments = ["installer"]
        if preview { arguments.append("--dry-run") }
        if debug { arguments.append("--debug") }
        arguments.append("--gui-remove")
        arguments += paths
        return MoleInvocation(
            label: preview ? "Preview installer cleanup" : "Remove installer files",
            arguments: arguments,
            risk: preview ? .preview : .destructiveMutation,
            environment: preview ? [:] : confirmed
        )
    }

    enum TouchIDAction: String, CaseIterable, Identifiable {
        case enable
        case disable

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    static let touchIDStatus = MoleInvocation(
        label: "Check Touch ID configuration",
        arguments: ["touchid", "--gui-status"],
        risk: .readOnly
    )

    static func touchID(_ action: TouchIDAction, preview: Bool = false) -> MoleInvocation {
        var arguments = ["touchid", action.rawValue]
        if preview { arguments.append("--dry-run") }
        return MoleInvocation(
            label: preview ? "Preview Touch ID \(action.rawValue)" : "\(action.title) Touch ID",
            arguments: arguments,
            risk: preview ? .preview : .privilegedMutation,
            environment: preview ? [:] : confirmed
        )
    }
}

private extension String {
    var trimmedNil: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

enum MoleFeature: String, CaseIterable, Identifiable {
    case overview
    case clean
    case uninstall
    case optimize
    case analyze
    case status
    case history
    case purge
    case installers
    case touchID
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .clean: "Clean"
        case .uninstall: "Uninstall"
        case .optimize: "Optimize"
        case .analyze: "Analyze"
        case .status: "Status"
        case .history: "History"
        case .purge: "Project Purge"
        case .installers: "Installers"
        case .touchID: "Touch ID"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .clean: "sparkles"
        case .uninstall: "app.badge.fill"
        case .optimize: "gauge.with.dots.needle.67percent"
        case .analyze: "chart.pie.fill"
        case .status: "waveform.path.ecg"
        case .history: "clock.arrow.circlepath"
        case .purge: "shippingbox.fill"
        case .installers: "externaldrive.badge.minus"
        case .touchID: "touchid"
        case .about: "info.circle.fill"
        }
    }

    static let toolkit: [MoleFeature] = [.overview, .clean, .uninstall, .optimize, .analyze, .status]
    static let storage: [MoleFeature] = [.history, .purge, .installers]
    static let settings: [MoleFeature] = [.touchID, .about]
}

struct InstalledApplication: Decodable, Identifiable, Hashable {
    let name: String
    let bundleID: String
    let source: String
    let uninstallName: String
    let path: String
    let size: String

    var id: String { path }

    private enum CodingKeys: String, CodingKey {
        case name
        case bundleID = "bundleId"
        case source
        case uninstallName
        case path
        case size
    }
}

struct DiskAnalysis: Decodable {
    struct Entry: Decodable, Identifiable, Hashable {
        let name: String
        let path: String
        let size: Int64
        let isDir: Bool

        var id: String { path }

        private enum CodingKeys: String, CodingKey {
            case name, path, size, isDir
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decode(String.self, forKey: .name)
            path = try values.decode(String.self, forKey: .path)
            size = try values.decode(Int64.self, forKey: .size)
            // Mole's large_files rows are always files and omit is_dir.
            isDir = try values.decodeIfPresent(Bool.self, forKey: .isDir) ?? false
        }
    }

    let path: String
    let overview: Bool
    let entries: [Entry]
    let largeFiles: [Entry]?
    let totalSize: Int64
    let totalFiles: Int?
}

struct InstallerCandidate: Decodable, Identifiable, Hashable {
    let name: String
    let path: String
    let source: String
    let size: String
    let sizeBytes: Int64

    var id: String { path }
}

struct PurgeCandidate: Decodable, Identifiable, Hashable {
    let path: String
    let displayPath: String
    let projectPath: String
    let artifact: String
    let sizeKb: Int64
    let sizeUnknown: Bool
    let recent: Bool
    let age: String
    let cloud: Bool

    var id: String { path }
    var sizeBytes: Int64 { sizeKb * 1_024 }
    var recommended: Bool { !recent && !cloud && !sizeUnknown }
}

struct WhitelistCatalog: Decodable, Hashable {
    struct Item: Decodable, Identifiable, Hashable {
        let name: String
        let pattern: String
        let category: String
        let selected: Bool

        var id: String { pattern }
    }

    let mode: String
    let configPath: String
    let items: [Item]
    let customPatterns: [String]
}

struct PurgePathsCatalog: Decodable, Hashable {
    struct PathItem: Decodable, Identifiable, Hashable {
        let path: String
        let exists: Bool

        var id: String { path }
    }

    let configPath: String
    let usingCustom: Bool
    let paths: [PathItem]
    let defaults: [String]
}

struct TrashResult: Decodable, Identifiable, Hashable {
    let path: String
    let status: String
    let error: String?

    var id: String { path }
}

struct TouchIDStatus: Decodable, Hashable {
    let supported: Bool
    let configured: Bool
    let location: String
}

struct StatusSnapshot: Decodable {
    struct Hardware: Decodable {
        let model: String?
        let cpuModel: String?
        let totalRam: String?
        let diskSize: String?
        let osVersion: String?
    }

    struct CPU: Decodable {
        let usage: Double
        let load1: Double?
        let load5: Double?
        let load15: Double?
        let coreCount: Int?
    }

    struct Memory: Decodable {
        let used: Int64
        let total: Int64
        let available: Int64?
        let usedPercent: Double
        let swapUsed: Int64?
        let swapTotal: Int64?
    }

    struct Disk: Decodable, Identifiable {
        let mount: String
        let used: Int64
        let total: Int64
        let usedPercent: Double
        let external: Bool
        let smartStatus: String?
        let purgeable: Int64?

        var id: String { mount }
    }

    struct Battery: Decodable, Identifiable {
        let percent: Int
        let status: String
        let health: String?
        let cycleCount: Int?
        let capacity: Int?

        var id: String { "\(status)-\(cycleCount ?? 0)" }
    }

    struct Network: Decodable, Identifiable {
        let name: String
        let rxRateMbs: Double
        let txRateMbs: Double
        let ip: String?

        var id: String { name }
    }

    struct ProcessInfo: Decodable, Identifiable {
        let pid: Int
        let name: String
        let cpu: Double
        let memory: Double
        let memoryBytes: Int64?

        var id: Int { pid }
    }

    let collectedAt: String?
    let host: String
    let uptime: String
    let hardware: Hardware?
    let healthScore: Int
    let healthScoreMsg: String?
    let cpu: CPU
    let memory: Memory
    let disks: [Disk]
    let trashSize: Int64?
    let network: [Network]?
    let batteries: [Battery]?
    let topProcesses: [ProcessInfo]?
    let zombieCount: Int?
}

struct HistoryReport: Decodable {
    struct Logs: Decodable {
        let operations: String
        let deletions: String
    }

    struct Actions: Decodable {
        let removed: Int
        let trashed: Int
        let skipped: Int
        let failed: Int
        let rebuilt: Int
        let other: Int
    }

    struct Session: Decodable, Identifiable {
        let command: String
        let startedAt: String
        let endedAt: String?
        let items: Int
        let size: String
        let operationCount: Int
        let failedTasks: Int
        let actions: Actions

        var id: String { "\(startedAt)-\(command)" }
    }

    struct Deletion: Decodable, Identifiable {
        let timestamp: String
        let mode: String
        let status: String
        let sizeKb: Int?
        let path: String

        var id: String { "\(timestamp)-\(path)" }
    }

    let logs: Logs
    let limit: Int
    let sessions: [Session]
    let deletions: [Deletion]
}

struct CommandResult {
    let invocation: MoleInvocation
    let standardOutput: String
    let standardError: String
    let exitCode: Int32
    let cancelled: Bool

    var succeeded: Bool { exitCode == 0 && !cancelled }

    var displayOutput: String {
        [standardOutput, standardError]
            .filter { !$0.isEmpty }
            .joined(separator: standardOutput.isEmpty || standardError.isEmpty ? "" : "\n")
    }
}

enum ByteFormat {
    static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static func string(_ value: Int64) -> String {
        formatter.string(fromByteCount: value)
    }
}
