import AppKit
import Foundation
import SwiftUI

struct UninstallView: View {
    @EnvironmentObject private var runner: MoleRunner
    @State private var search = ""
    @State private var selection = Set<String>()
    @State private var permanent = false
    @State private var debug = false
    @State private var confirmUninstall = false

    private var filteredApps: [InstalledApplication] {
        let apps = runner.installedApps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !search.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.bundleID.localizedCaseInsensitiveContains(search)
                || $0.path.localizedCaseInsensitiveContains(search)
        }
    }

    private var selectedApps: [InstalledApplication] {
        runner.installedApps.filter { selection.contains($0.id) }
    }

    var body: some View {
        let apps = filteredApps
        return FeaturePage(
            title: "Uninstall",
            subtitle: "Remove applications plus related launch agents, preferences, caches, and leftovers.",
            icon: MoleFeature.uninstall.icon
        ) {
            SafetyNote(
                text: permanent
                    ? "Permanent mode bypasses Trash. Selected application data cannot be recovered."
                    : "Default removal moves eligible files to Trash. Mole rescans applications and rechecks identity before every change.",
                destructive: permanent
            )

            MoleCard(
                title: "Applications",
                subtitle: runner.installedApps.isEmpty
                    ? "Scan the current application inventory."
                    : "\(runner.installedApps.count) found · \(selection.count) selected"
            ) {
                HStack {
                    TextField("Search names, bundle IDs, or paths", text: $search)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        selection.removeAll()
                        runner.refreshInstalledApps()
                    } label: {
                        Label(runner.installedApps.isEmpty ? "Scan Apps" : "Rescan", systemImage: "arrow.clockwise")
                    }
                    .disabled(runner.isRunning)
                    if !apps.isEmpty {
                        Button("Select Visible") {
                            selection.formUnion(apps.map(\.id))
                        }
                        Button("Clear") { selection.removeAll() }
                            .disabled(selection.isEmpty)
                    }
                }

                if runner.installedApps.isEmpty {
                    ContentUnavailableView(
                        "No Application Inventory",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("Scan to inspect installed application bundles.")
                    )
                    .frame(height: 250)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(apps) { app in
                                applicationRow(app)
                                if app.id != apps.last?.id {
                                    Divider().padding(.leading, 38)
                                }
                            }
                        }
                    }
                    .frame(height: 330)
                    .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            MoleCard(title: "Removal options") {
                Toggle("Delete permanently instead of moving to Trash", isOn: $permanent)
                    .tint(.red)
                Toggle("Detailed activity", isOn: $debug)
            }

            HStack {
                Button {
                    runner.runCapture(command(preview: true))
                } label: {
                    Label("Preview Selected", systemImage: "eye")
                }
                .standardButton()
                .disabled(selection.isEmpty || runner.isRunning)

                Button {
                    confirmUninstall = true
                } label: {
                    Label("Uninstall Selected…", systemImage: "trash")
                }
                .primaryButton()
                .disabled(selection.isEmpty || runner.isRunning)
            }
        }
        .task {
            if runner.installedApps.isEmpty && !runner.isRunning {
                runner.refreshInstalledApps()
            }
        }
        .alert(permanent ? "Permanently delete selected applications?" : "Move selected applications to Trash?", isPresented: $confirmUninstall) {
            Button("Cancel", role: .cancel) {}
            Button(permanent ? "Delete Permanently" : "Uninstall", role: .destructive) {
                runner.runCapture(command(preview: false)) { result in
                    guard result.succeeded else { return }
                    selection.removeAll()
                    runner.refreshInstalledApps()
                }
            }
        } message: {
            Text(permanent
                 ? "Mole will remove \(selection.count) selected applications and eligible related files without recovery. Preview first."
                 : "Mole will move \(selection.count) selected applications and eligible related files to Trash. Shared and protected data stays untouched.")
        }
    }

    private func command(preview: Bool) -> MoleInvocation {
        MoleCommands.uninstall(
            paths: selectedApps.map(\.path),
            preview: preview,
            permanent: permanent,
            debug: debug
        )
    }

    private func applicationRow(_ app: InstalledApplication) -> some View {
        Button {
            toggle(app.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection.contains(app.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selection.contains(app.id) ? .green : .secondary)
                Image(systemName: "app.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.body.weight(.medium))
                    Text(app.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(app.size)
                        .font(.body.monospacedDigit())
                    Text(app.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}

struct AnalyzeView: View {
    @EnvironmentObject private var runner: MoleRunner
    @State private var path = FileManager.default.homeDirectoryForCurrentUser.path
    @State private var selection = Set<String>()
    @State private var confirmTrash = false

    private var sortedEntries: [DiskAnalysis.Entry] {
        runner.diskAnalysis?.entries.sorted { $0.size > $1.size } ?? []
    }

    private var sortedLargeFiles: [DiskAnalysis.Entry] {
        runner.diskAnalysis?.largeFiles?.sorted { $0.size > $1.size } ?? []
    }

    var body: some View {
        let entries = sortedEntries
        let largeFiles = sortedLargeFiles
        return FeaturePage(
            title: "Analyze",
            subtitle: "Explore folder sizes, reveal files, select items, and move reviewed items to Trash.",
            icon: MoleFeature.analyze.icon
        ) {
            SafetyNote(text: "Analysis is read-only. Selected items move to Trash only after confirmation and Mole's final path checks.")

            MoleCard(title: "Location") {
                FolderField(path: $path, prompt: "Folder to analyze")
                HStack {
                    Button {
                        selection.removeAll()
                        runner.analyze(path: path)
                    } label: {
                        Label("Analyze Folder", systemImage: "chart.pie")
                    }
                    .primaryButton()
                    .disabled(path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || runner.isRunning)

                    Button("Mac Overview") {
                        selection.removeAll()
                        runner.analyze(path: nil)
                    }
                    .standardButton()
                    .disabled(runner.isRunning)
                }
            }

            if let analysis = runner.diskAnalysis {
                MoleCard(
                    title: analysis.overview ? "Mac Overview" : analysis.path,
                    subtitle: "\(ByteFormat.string(analysis.totalSize))" + (analysis.totalFiles.map { " · \($0.formatted()) files" } ?? "")
                ) {
                    HStack {
                        Text("\(selection.count) selected")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Select Listed") {
                            selection.formUnion(entries.map(\.path))
                        }
                        .disabled(entries.isEmpty)
                        Button("Clear") { selection.removeAll() }
                            .disabled(selection.isEmpty)
                    }

                    if entries.isEmpty {
                        ContentUnavailableView("No Contents", systemImage: "folder", description: Text("Mole found no sized entries."))
                            .frame(height: 180)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(entries) { entry in
                                analysisRow(entry)
                                if entry.id != entries.last?.id { Divider() }
                            }
                        }
                    }
                }

                if !largeFiles.isEmpty {
                    MoleCard(title: "Large files", subtitle: "Files at least 100 MB found in this analysis") {
                        LazyVStack(spacing: 0) {
                            ForEach(largeFiles) { entry in
                                analysisRow(entry)
                                if entry.id != largeFiles.last?.id { Divider() }
                            }
                        }
                    }
                }

                HStack {
                    Button {
                        confirmTrash = true
                    } label: {
                        Label("Move Selected to Trash…", systemImage: "trash")
                    }
                    .primaryButton()
                    .disabled(selection.isEmpty || runner.isRunning)
                }
            }

            if !runner.trashResults.isEmpty {
                MoleCard(title: "Last Trash action") {
                    ForEach(runner.trashResults) { result in
                        HStack {
                            Image(systemName: result.status == "trashed" ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.status == "trashed" ? .green : .red)
                            Text(result.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(result.status.capitalized)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .alert("Move selected items to Trash?", isPresented: $confirmTrash) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) {
                let paths = Array(selection).sorted()
                let previousAnalysis = runner.diskAnalysis
                runner.moveAnalyzedItemsToTrash(paths: paths) { succeeded in
                    guard succeeded else { return }
                    selection.removeAll()
                    runner.analyze(path: previousAnalysis?.overview == true ? nil : previousAnalysis?.path)
                }
            }
        } message: {
            Text("\(selection.count) selected items will move to macOS Trash. They remain recoverable until Trash is emptied.")
        }
    }

    private func analysisRow(_ entry: DiskAnalysis.Entry) -> some View {
        HStack(spacing: 10) {
            Button {
                toggle(entry.path)
            } label: {
                Image(systemName: selection.contains(entry.path) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selection.contains(entry.path) ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(entry.name)")
            .accessibilityValue(selection.contains(entry.path) ? "Selected" : "Not selected")

            Image(systemName: entry.isDir ? "folder.fill" : "doc.fill")
                .foregroundStyle(entry.isDir ? .blue : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                Text(entry.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(ByteFormat.string(entry.size))
                .font(.body.monospacedDigit())
            if entry.isDir {
                Button {
                    path = entry.path
                    selection.removeAll()
                    runner.analyze(path: entry.path)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .help("Analyze this folder")
            }
            Button {
                runner.reveal(path: entry.path)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 8)
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}

struct StatusView: View {
    @EnvironmentObject private var runner: MoleRunner
    @Environment(\.scenePhase) private var scenePhase
    @State private var autoRefresh = false

    var body: some View {
        FeaturePage(
            title: "Status",
            subtitle: "Live health, hardware, memory, storage, network, power, and process metrics.",
            icon: MoleFeature.status.icon
        ) {
            HStack {
                Button {
                    runner.refreshStatus()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .primaryButton()
                .disabled(runner.isRunning)

                Toggle("Refresh every 5 seconds while active", isOn: $autoRefresh)
                    .toggleStyle(.switch)
                Spacer()
            }

            if let status = runner.status {
                statusCards(status)
                processCard(status)
            } else {
                MoleCard {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Waiting for first health snapshot…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task {
            if runner.status == nil && !runner.isRunning {
                runner.refreshStatus()
            }
        }
        .task(id: autoRefresh && scenePhase == .active && !runner.isRunning) {
            guard autoRefresh, scenePhase == .active, !runner.isRunning else { return }
            await runner.monitorStatus()
        }
    }

    @ViewBuilder
    private func statusCards(_ status: StatusSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            MetricCard(
                title: "Health",
                value: "\(status.healthScore)",
                detail: status.healthScoreMsg ?? "\(status.host) · uptime \(status.uptime)",
                progress: Double(status.healthScore),
                color: status.healthScore >= 80 ? .green : .orange
            )
            MetricCard(
                title: "CPU",
                value: String(format: "%.1f%%", status.cpu.usage),
                detail: String(format: "Load %.2f · %d cores", status.cpu.load1 ?? 0, status.cpu.coreCount ?? 0),
                progress: status.cpu.usage,
                color: usageColor(status.cpu.usage)
            )
            MetricCard(
                title: "Memory",
                value: String(format: "%.1f%%", status.memory.usedPercent),
                detail: "\(ByteFormat.string(status.memory.used)) / \(ByteFormat.string(status.memory.total))",
                progress: status.memory.usedPercent,
                color: usageColor(status.memory.usedPercent)
            )
            ForEach(status.disks) { disk in
                MetricCard(
                    title: disk.mount == "/" ? "Storage" : disk.mount,
                    value: ByteFormat.string(max(0, disk.total - disk.used)),
                    detail: "Free · \(String(format: "%.1f%%", disk.usedPercent)) used · SMART \(disk.smartStatus ?? "unknown")",
                    progress: disk.usedPercent,
                    color: usageColor(disk.usedPercent)
                )
            }
            if let battery = status.batteries?.first {
                MetricCard(
                    title: "Battery",
                    value: "\(battery.percent)%",
                    detail: "\(battery.status) · \(battery.health ?? "Unknown") · \(battery.cycleCount ?? 0) cycles",
                    progress: Double(battery.percent),
                    color: battery.health == "Good" ? .green : .orange
                )
            }
            if let trash = status.trashSize {
                MetricCard(title: "Trash", value: ByteFormat.string(trash), detail: "Current Trash size", progress: nil)
            }
        }

        if let network = status.network, !network.isEmpty {
            MoleCard(title: "Network") {
                ForEach(network) { interface in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(interface.name).font(.headline)
                            if let ip = interface.ip { Text(ip).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(String(format: "↓ %.2f  ↑ %.2f MB/s", interface.rxRateMbs, interface.txRateMbs))
                            .font(.body.monospacedDigit())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func processCard(_ status: StatusSnapshot) -> some View {
        if let processes = status.topProcesses, !processes.isEmpty {
            MoleCard(title: "Top processes", subtitle: "\(status.zombieCount ?? 0) zombie processes") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    GridRow {
                        Text("Process").font(.caption.bold())
                        Text("PID").font(.caption.bold())
                        Text("CPU").font(.caption.bold())
                        Text("Memory").font(.caption.bold())
                    }
                    Divider()
                    ForEach(processes.prefix(10)) { process in
                        GridRow {
                            Text(process.name).lineLimit(1)
                            Text("\(process.pid)").monospacedDigit()
                            Text(String(format: "%.1f%%", process.cpu)).monospacedDigit()
                            Text(process.memoryBytes.map(ByteFormat.string) ?? String(format: "%.1f%%", process.memory)).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private func usageColor(_ value: Double) -> Color {
        value < 75 ? .green : (value < 90 ? .orange : .red)
    }
}

struct HistoryView: View {
    @EnvironmentObject private var runner: MoleRunner
    @State private var limit = 30

    var body: some View {
        FeaturePage(
            title: "History",
            subtitle: "Review recorded cleanup sessions and file actions.",
            icon: MoleFeature.history.icon
        ) {
            HStack {
                Stepper("Sessions: \(limit)", value: $limit, in: 1...200, step: 10)
                    .frame(width: 180)
                Button {
                    runner.refreshHistory(limit: limit)
                } label: {
                    Label("Load History", systemImage: "arrow.clockwise")
                }
                .primaryButton()
                .disabled(runner.isRunning)
                Button("Export JSON…") {
                    runner.exportHistory()
                }
                .standardButton()
                .disabled(runner.history == nil)
            }

            if let history = runner.history {
                MoleCard(title: "Sessions", subtitle: "\(history.sessions.count) recent sessions") {
                    if history.sessions.isEmpty {
                        Text("No recorded cleanup sessions.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(history.sessions) { session in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(session.command.capitalized).font(.headline)
                                        Text(session.startedAt).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(session.size).monospacedDigit()
                                        Text("\(session.items) items · \(session.failedTasks) failed")
                                            .font(.caption)
                                            .foregroundStyle(session.failedTasks > 0 ? .orange : .secondary)
                                    }
                                }
                                .padding(.vertical, 8)
                                if session.id != history.sessions.last?.id { Divider() }
                            }
                        }
                    }
                }

                MoleCard(title: "Recent file actions", subtitle: "Paths may no longer exist") {
                    if history.deletions.isEmpty {
                        Text("No file actions recorded.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(history.deletions.prefix(100)) { deletion in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(deletion.path)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Text("\(deletion.timestamp) · \(deletion.mode)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(deletion.status.capitalized)
                                        .font(.caption.weight(.semibold))
                                }
                                .padding(.vertical, 7)
                                if deletion.id != history.deletions.prefix(100).last?.id { Divider() }
                            }
                        }
                    }
                }
            } else {
                SafetyNote(text: "History is read-only. Mole stores its operation log in your user Library.")
            }
        }
    }
}

struct PurgeView: View {
    @EnvironmentObject private var runner: MoleRunner
    @State private var includeEmpty = false
    @State private var debug = false
    @State private var search = ""
    @State private var selection = Set<String>()
    @State private var confirmPurge = false
    @State private var showingPaths = false

    private var filteredCandidates: [PurgeCandidate] {
        let candidates = runner.purgeCandidates.sorted { $0.sizeKb > $1.sizeKb }
        guard !search.isEmpty else { return candidates }
        return candidates.filter {
            $0.path.localizedCaseInsensitiveContains(search)
                || $0.projectPath.localizedCaseInsensitiveContains(search)
                || $0.artifact.localizedCaseInsensitiveContains(search)
        }
    }

    private var selectedCandidates: [PurgeCandidate] {
        runner.purgeCandidates.filter { selection.contains($0.id) }
    }

    private var selectedSize: Int64 {
        selectedCandidates.reduce(0) { $0 + ($1.sizeUnknown ? 0 : $1.sizeBytes) }
    }

    var body: some View {
        let candidates = filteredCandidates
        return FeaturePage(
            title: "Project Purge",
            subtitle: "Find rebuildable dependencies, build products, test caches, and generated artifacts.",
            icon: MoleFeature.purge.icon
        ) {
            SafetyNote(text: "Purge permanently deletes confirmed artifacts. Recent, cloud-synced, or size-unknown items start unselected.", destructive: true)

            MoleCard(title: "Scan") {
                Toggle("Include empty artifact directories", isOn: $includeEmpty)
                Toggle("Detailed activity", isOn: $debug)
                HStack {
                    Button {
                        scanCandidates()
                    } label: {
                        Label("Scan Projects", systemImage: "magnifyingglass")
                    }
                    .primaryButton()
                    .disabled(runner.isRunning)

                    Button("Scan Paths…") { showingPaths = true }
                        .disabled(runner.isRunning)
                }
            }

            MoleCard(
                title: "Artifacts",
                subtitle: runner.purgeCandidates.isEmpty
                    ? "Scan to build a current safe plan."
                    : "\(runner.purgeCandidates.count) found · \(selection.count) selected · \(ByteFormat.string(selectedSize)) known size"
            ) {
                HStack {
                    TextField("Search projects, paths, or artifact names", text: $search)
                        .textFieldStyle(.roundedBorder)
                    Button("Select Recommended") {
                        selection = Set(runner.purgeCandidates.filter(\.recommended).map(\.id))
                    }
                    .disabled(runner.purgeCandidates.isEmpty)
                    Button("Clear") { selection.removeAll() }
                        .disabled(selection.isEmpty)
                }

                if runner.purgeCandidates.isEmpty {
                    ContentUnavailableView("No Artifact Plan", systemImage: "shippingbox", description: Text("Scan configured project paths to find rebuildable artifacts."))
                        .frame(height: 230)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(candidates) { candidate in
                                purgeRow(candidate)
                                if candidate.id != candidates.last?.id { Divider().padding(.leading, 34) }
                            }
                        }
                    }
                    .frame(height: 350)
                }
            }

            HStack {
                Button {
                    runner.runCapture(purgeCommand(preview: true))
                } label: {
                    Label("Preview Selected", systemImage: "eye")
                }
                .standardButton()
                .disabled(selection.isEmpty || runner.isRunning)

                Button {
                    confirmPurge = true
                } label: {
                    Label("Purge Selected…", systemImage: "trash")
                }
                .primaryButton()
                .disabled(selection.isEmpty || runner.isRunning)
            }
        }
        .sheet(isPresented: $showingPaths) {
            PurgePathsEditorView()
                .environmentObject(runner)
        }
        .alert("Permanently delete selected artifacts?", isPresented: $confirmPurge) {
            Button("Cancel", role: .cancel) {}
            Button("Purge", role: .destructive) {
                runner.runCapture(purgeCommand(preview: false)) { result in
                    guard result.succeeded else { return }
                    scanCandidates()
                }
            }
        } message: {
            let warnings = selectedCandidates.filter { !$0.recommended }.count
            Text("\(selection.count) artifacts will be permanently deleted. Known size: \(ByteFormat.string(selectedSize)). \(warnings) selected items need extra review because they are recent, cloud-synced, or size-unknown.")
        }
    }

    private func scanCandidates() {
        selection.removeAll()
        runner.refreshPurgeCandidates(includeEmpty: includeEmpty, debug: debug) { candidates in
            selection = Set(candidates.filter(\.recommended).map(\.id))
        }
    }

    private func purgeCommand(preview: Bool) -> MoleInvocation {
        MoleCommands.purgeRemove(
            paths: selectedCandidates.map(\.path),
            preview: preview,
            includeEmpty: includeEmpty,
            debug: debug
        )
    }

    private func purgeRow(_ candidate: PurgeCandidate) -> some View {
        Button {
            toggle(candidate.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection.contains(candidate.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selection.contains(candidate.id) ? .green : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(candidate.artifact).font(.body.weight(.medium))
                        if candidate.recent { badge("Recent", color: .orange) }
                        if candidate.cloud { badge("Cloud", color: .blue) }
                        if candidate.sizeUnknown { badge("Unknown size", color: .orange) }
                    }
                    Text(candidate.displayPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(candidate.sizeUnknown ? "Unknown" : ByteFormat.string(candidate.sizeBytes))
                        .monospacedDigit()
                    Text(candidate.age)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }

    private func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}

struct InstallersView: View {
    @EnvironmentObject private var runner: MoleRunner
    @State private var debug = false
    @State private var search = ""
    @State private var selection = Set<String>()
    @State private var confirmRemoval = false

    private var filteredCandidates: [InstallerCandidate] {
        let candidates = runner.installerCandidates.sorted { $0.sizeBytes > $1.sizeBytes }
        guard !search.isEmpty else { return candidates }
        return candidates.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.path.localizedCaseInsensitiveContains(search)
                || $0.source.localizedCaseInsensitiveContains(search)
        }
    }

    private var selectedCandidates: [InstallerCandidate] {
        runner.installerCandidates.filter { selection.contains($0.id) }
    }

    private var selectedSize: Int64 {
        selectedCandidates.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        let candidates = filteredCandidates
        return FeaturePage(
            title: "Installers",
            subtitle: "Find DMG, PKG, MPKG, ISO, XIP, and installer ZIP files in supported locations.",
            icon: MoleFeature.installers.icon
        ) {
            SafetyNote(text: "Mole rescans every selected path and verifies file identity and size immediately before permanent removal.", destructive: true)

            MoleCard(title: "Scan") {
                Toggle("Detailed activity", isOn: $debug)
                Button {
                    scanInstallers()
                } label: {
                    Label("Scan Installer Files", systemImage: "magnifyingglass")
                }
                .primaryButton()
                .disabled(runner.isRunning)
            }

            MoleCard(
                title: "Installer files",
                subtitle: runner.installerCandidates.isEmpty
                    ? "Scan supported download and cache locations."
                    : "\(runner.installerCandidates.count) found · \(selection.count) selected · \(ByteFormat.string(selectedSize))"
            ) {
                HStack {
                    TextField("Search files, paths, or sources", text: $search)
                        .textFieldStyle(.roundedBorder)
                    Button("Select All") {
                        selection = Set(candidates.map(\.id))
                    }
                    .disabled(candidates.isEmpty)
                    Button("Clear") { selection.removeAll() }
                        .disabled(selection.isEmpty)
                }

                if runner.installerCandidates.isEmpty {
                    ContentUnavailableView("No Installer Inventory", systemImage: "externaldrive", description: Text("Scan to review installer files before removal."))
                        .frame(height: 230)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(candidates) { candidate in
                                installerRow(candidate)
                                if candidate.id != candidates.last?.id { Divider().padding(.leading, 34) }
                            }
                        }
                    }
                    .frame(height: 350)
                }
            }

            HStack {
                Button {
                    runner.runCapture(installerCommand(preview: true))
                } label: {
                    Label("Preview Selected", systemImage: "eye")
                }
                .standardButton()
                .disabled(selection.isEmpty || runner.isRunning)

                Button {
                    confirmRemoval = true
                } label: {
                    Label("Remove Selected…", systemImage: "trash")
                }
                .primaryButton()
                .disabled(selection.isEmpty || runner.isRunning)
            }
        }
        .alert("Permanently remove selected installer files?", isPresented: $confirmRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                runner.runCapture(installerCommand(preview: false)) { result in
                    guard result.succeeded else { return }
                    scanInstallers()
                }
            }
        } message: {
            Text("\(selection.count) files totaling \(ByteFormat.string(selectedSize)) will be permanently removed. Mole rebuilds the current plan and checks each file immediately before removal.")
        }
    }

    private func scanInstallers() {
        selection.removeAll()
        runner.refreshInstallerCandidates(debug: debug)
    }

    private func installerCommand(preview: Bool) -> MoleInvocation {
        MoleCommands.installersRemove(paths: selectedCandidates.map(\.path), preview: preview, debug: debug)
    }

    private func installerRow(_ candidate: InstallerCandidate) -> some View {
        HStack(spacing: 10) {
            Button {
                if selection.contains(candidate.id) { selection.remove(candidate.id) } else { selection.insert(candidate.id) }
            } label: {
                HStack(spacing: 10) {
                Image(systemName: selection.contains(candidate.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selection.contains(candidate.id) ? .green : .secondary)
                Image(systemName: "doc.zipper")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name).font(.body.weight(.medium))
                    Text(candidate.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(candidate.size).monospacedDigit()
                    Text(candidate.source).font(.caption).foregroundStyle(.secondary)
                }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                runner.reveal(path: candidate.path)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
        }
        .padding(.vertical, 8)
    }
}

struct PurgePathsEditorView: View {
    @EnvironmentObject private var runner: MoleRunner
    @Environment(\.dismiss) private var dismiss
    @State private var paths: [String] = []
    @State private var newPath = ""
    @State private var loadedCatalog: PurgePathsCatalog?

    var body: some View {
        NavigationStack {
            Group {
                if let catalog = runner.purgePathsCatalog {
                    List {
                        Section {
                            Text("Only these folders are scanned for rebuildable project artifacts. Mole still applies project and path safety checks.")
                                .foregroundStyle(.secondary)
                        }

                        Section("Scan paths") {
                            ForEach(paths, id: \.self) { path in
                                HStack {
                                    Image(systemName: FileManager.default.fileExists(atPath: expanded(path)) ? "folder.fill" : "folder.badge.questionmark")
                                        .foregroundStyle(FileManager.default.fileExists(atPath: expanded(path)) ? .blue : .orange)
                                    Text(path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button {
                                        paths.removeAll { $0 == path }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove path")
                                }
                            }

                            HStack {
                                TextField("Absolute folder path", text: $newPath)
                                Button("Choose…") { chooseFolder() }
                                Button {
                                    addPath()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .disabled(normalizedNewPath == nil)
                            }
                        }

                        Section {
                            Button("Use Recommended Paths") {
                                paths = catalog.defaults
                            }
                            Text(catalog.usingCustom ? "Custom paths currently active." : "Recommended paths currently active.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        if runner.isRunning {
                            ProgressView()
                            Text("Loading scan paths…")
                        } else {
                            Text("Scan paths could not be loaded.")
                            Button("Retry") { runner.refreshPurgePaths() }
                        }
                        Text(runner.presentedError ?? "").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Project Scan Paths")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        runner.savePurgePaths(paths) { succeeded in
                            if succeeded { dismiss() }
                        }
                    }
                    .disabled(loadedCatalog == nil || paths.isEmpty || runner.isRunning)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .onAppear {
            runner.refreshPurgePaths()
        }
        .onChange(of: runner.purgePathsCatalog, initial: true) { _, updated in
            guard let updated, updated != loadedCatalog else { return }
            loadedCatalog = updated
            paths = updated.paths.map(\.path)
        }
    }

    private var normalizedNewPath: String? {
        let value = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\n"), !value.contains("\r") else { return nil }
        guard value.hasPrefix("/") || value.hasPrefix("~/") else { return nil }
        guard !paths.contains(value) else { return nil }
        return value
    }

    private func expanded(_ path: String) -> String {
        NSString(string: path).expandingTildeInPath
    }

    private func addPath() {
        guard let path = normalizedNewPath else { return }
        paths.append(path)
        newPath = ""
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        if panel.runModal() == .OK, let path = panel.url?.path, !paths.contains(path) {
            paths.append(path)
        }
    }
}
