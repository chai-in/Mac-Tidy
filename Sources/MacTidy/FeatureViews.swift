import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var runner: MoleRunner
    @Binding var selection: MoleFeature?

    var body: some View {
        FeaturePage(
            title: "Mac Tidy",
            subtitle: "Native storage cleanup, application removal, optimization, analysis, and system health.",
            icon: "leaf.fill"
        ) {
            SafetyNote(text: "Mole builds every plan, rechecks selected paths before changes, and records cleanup activity. Preview is available before permanent actions.")

            if let status = runner.status {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    MetricCard(
                        title: "Health",
                        value: "\(status.healthScore)",
                        detail: status.healthScoreMsg ?? "Uptime \(status.uptime)",
                        progress: Double(status.healthScore),
                        color: healthColor(status.healthScore)
                    )
                    MetricCard(
                        title: "Memory",
                        value: String(format: "%.0f%%", status.memory.usedPercent),
                        detail: "\(ByteFormat.string(status.memory.used)) used",
                        progress: status.memory.usedPercent,
                        color: usageColor(status.memory.usedPercent)
                    )
                    if let disk = status.disks.first(where: { $0.mount == "/" }) ?? status.disks.first {
                        MetricCard(
                            title: "Storage",
                            value: ByteFormat.string(max(0, disk.total - disk.used)),
                            detail: "Free · \(Int(disk.usedPercent.rounded()))% used",
                            progress: disk.usedPercent,
                            color: usageColor(disk.usedPercent)
                        )
                    }
                }
            } else {
                MoleCard {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(runner.isAvailable ? "Loading system health…" : "Bundled engine is unavailable.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            MoleCard(title: "Tools", subtitle: "Choose a task. Selection and confirmation stay in this app.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                    overviewButton(.clean, detail: "Caches, logs, leftovers")
                    overviewButton(.uninstall, detail: "Apps and related files")
                    overviewButton(.optimize, detail: "Caches and services")
                    overviewButton(.analyze, detail: "Browse disk usage")
                    overviewButton(.status, detail: "Live system health")
                    overviewButton(.purge, detail: "Build artifacts")
                    overviewButton(.installers, detail: "DMG, PKG, ISO, ZIP")
                    overviewButton(.history, detail: "Cleanup audit trail")
                }
            }

            Button {
                runner.refreshStatus()
            } label: {
                Label("Refresh Health", systemImage: "arrow.clockwise")
            }
            .standardButton()
            .disabled(runner.isRunning || !runner.isAvailable)
        }
    }

    private func overviewButton(_ feature: MoleFeature, detail: String) -> some View {
        Button {
            selection = feature
        } label: {
            HStack(spacing: 12) {
                Image(systemName: feature.icon)
                    .font(.title3)
                    .foregroundStyle(.green)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func healthColor(_ value: Int) -> Color {
        value >= 80 ? .green : (value >= 60 ? .orange : .red)
    }

    private func usageColor(_ value: Double) -> Color {
        value < 75 ? .green : (value < 90 ? .orange : .red)
    }
}

struct CleanView: View {
    @EnvironmentObject private var runner: MoleRunner
    @State private var externalPath = ""
    @State private var cleanExternal = false
    @State private var includeSystemCaches = false
    @State private var debug = false
    @State private var confirmClean = false
    @State private var showingProtections = false

    var body: some View {
        FeaturePage(
            title: "Clean",
            subtitle: "Remove known-safe caches, logs, temporary files, and abandoned application leftovers.",
            icon: MoleFeature.clean.icon
        ) {
            SafetyNote(text: "Preview performs the same scan without deleting. Full cleanup permanently removes eligible data and may empty Trash.", destructive: true)

            MoleCard(title: "Scope") {
                Toggle("Include protected system cache locations", isOn: $includeSystemCaches)
                Text(includeSystemCaches
                     ? "macOS will request administrator authentication when needed."
                     : "Only user-owned locations will be cleaned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Clean metadata from an external volume", isOn: $cleanExternal)
                if cleanExternal {
                    FolderField(path: $externalPath, prompt: "/Volumes/Drive", startAtVolumes: true)
                }
                Toggle("Detailed activity", isOn: $debug)
            }

            HStack {
                Button {
                    runner.runCapture(command(preview: true))
                } label: {
                    Label("Preview Cleanup", systemImage: "eye")
                }
                .standardButton()
                .disabled(actionDisabled)

                Button {
                    confirmClean = true
                } label: {
                    Label("Clean Now…", systemImage: "sparkles")
                }
                .primaryButton()
                .disabled(actionDisabled)

                Spacer()

                Button("Protected Items…") {
                    showingProtections = true
                }
                .disabled(runner.isRunning)
            }
        }
        .sheet(isPresented: $showingProtections) {
            WhitelistEditorView(mode: .clean)
                .environmentObject(runner)
        }
        .alert("Run full cleanup?", isPresented: $confirmClean) {
            Button("Cancel", role: .cancel) {}
            Button("Clean", role: .destructive) {
                runner.runCapture(command(preview: false))
            }
        } message: {
            Text("Eligible caches, logs, temporary files, Trash contents, and abandoned leftovers will be permanently removed. Review the preview first.")
        }
    }

    private var actionDisabled: Bool {
        runner.isRunning
            || (cleanExternal && externalPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func command(preview: Bool) -> MoleInvocation {
        MoleCommands.clean(
            preview: preview,
            externalPath: cleanExternal ? externalPath : nil,
            debug: debug,
            includeSystemCaches: includeSystemCaches
        )
    }
}

struct OptimizeView: View {
    @EnvironmentObject private var runner: MoleRunner
    @State private var debug = false
    @State private var confirmOptimize = false
    @State private var showingProtections = false

    var body: some View {
        FeaturePage(
            title: "Optimize",
            subtitle: "Refresh supported caches, databases, network state, and macOS services.",
            icon: MoleFeature.optimize.icon
        ) {
            SafetyNote(text: "Mole probes each task first, skips unavailable work, and requests administrator authentication only when required.")

            MoleCard(title: "Options") {
                Toggle("Detailed activity", isOn: $debug)
            }

            HStack {
                Button {
                    runner.runCapture(MoleCommands.optimize(preview: true, debug: debug))
                } label: {
                    Label("Preview Optimization", systemImage: "eye")
                }
                .standardButton()
                .disabled(runner.isRunning)

                Button {
                    confirmOptimize = true
                } label: {
                    Label("Optimize Now…", systemImage: "gauge.with.dots.needle.67percent")
                }
                .primaryButton()
                .disabled(runner.isRunning)

                Spacer()

                Button("Protected Tasks…") {
                    showingProtections = true
                }
                .disabled(runner.isRunning)
            }
        }
        .sheet(isPresented: $showingProtections) {
            WhitelistEditorView(mode: .optimize)
                .environmentObject(runner)
        }
        .alert("Apply optimization?", isPresented: $confirmOptimize) {
            Button("Cancel", role: .cancel) {}
            Button("Optimize") {
                runner.runCapture(MoleCommands.optimize(preview: false, debug: debug))
            }
        } message: {
            Text("Supported caches and services may restart or refresh. macOS will request administrator authentication when needed.")
        }
    }
}

struct TouchIDView: View {
    @EnvironmentObject private var runner: MoleRunner
    @State private var pendingAction: MoleCommands.TouchIDAction?

    var body: some View {
        FeaturePage(
            title: "Touch ID",
            subtitle: "Allow Touch ID for administrator authentication used by cleanup and optimization.",
            icon: MoleFeature.touchID.icon
        ) {
            SafetyNote(text: "Mole edits only the supported sudo PAM configuration. macOS handles administrator authentication.")

            MoleCard(title: "Current configuration") {
                if let status = runner.touchIDStatus {
                    LabeledContent("Hardware support", value: status.supported ? "Available" : "Not detected")
                    LabeledContent("Touch ID for sudo", value: status.configured ? "Enabled" : "Disabled")
                    if status.configured {
                        LabeledContent("Configuration", value: status.location == "sudo_local" ? "Local override" : "System file")
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Checking configuration…")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button {
                        runner.refreshTouchIDStatus()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(runner.isRunning)

                    Button("Preview Enable") {
                        runner.runCapture(MoleCommands.touchID(.enable, preview: true))
                    }
                    .disabled(runner.isRunning)

                    Button("Preview Disable") {
                        runner.runCapture(MoleCommands.touchID(.disable, preview: true))
                    }
                    .disabled(runner.isRunning)
                }
            }

            HStack {
                Button("Enable Touch ID…") { pendingAction = .enable }
                    .primaryButton()
                    .disabled(runner.isRunning)
                Button("Disable Touch ID…") { pendingAction = .disable }
                    .standardButton()
                    .disabled(runner.isRunning)
            }
        }
        .task {
            if runner.touchIDStatus == nil && !runner.isRunning {
                runner.refreshTouchIDStatus()
            }
        }
        .alert("Change administrator authentication?", isPresented: Binding(
            get: { pendingAction != nil },
            set: { if !$0 { pendingAction = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingAction = nil }
            Button(pendingAction?.title ?? "Continue") {
                if let action = pendingAction {
                    runner.runCapture(MoleCommands.touchID(action)) { result in
                        if result.succeeded { runner.refreshTouchIDStatus() }
                    }
                }
                pendingAction = nil
            }
        } message: {
            Text("macOS will request administrator authentication, then Mole will update its supported PAM entry.")
        }
    }
}

struct AboutView: View {
    @EnvironmentObject private var runner: MoleRunner

    var body: some View {
        FeaturePage(
            title: "About Mac Tidy",
            subtitle: "Independent open-source macOS interface powered by Mole.",
            icon: MoleFeature.about.icon
        ) {
            MoleCard(title: "Self-contained") {
                LabeledContent("App version", value: AppMetadata.version)
                LabeledContent("Bundled Mole", value: runner.moleVersion)
                LabeledContent("Engine source", value: "Mole V\(AppMetadata.bundledMoleVersion)")
                LabeledContent("Engine commit", value: String(AppMetadata.bundledMoleCommit.prefix(12)))
                Text("The engine ships inside the application and is replaced only by an application update. No separate Mole installation is required.")
                    .foregroundStyle(.secondary)
            }

            MoleCard(title: "Open source", subtitle: "Mac Tidy and its modified Mole engine are distributed under GNU GPL v3.") {
                HStack {
                    Button("View Bundled License") {
                        runner.openBundledLicense()
                    }
                    .standardButton()
                    .disabled(runner.bundledLicenseURL == nil)

                    Link("Mac Tidy Source", destination: URL(string: "https://github.com/chai-in/Mac-Tidy")!)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Text("Copyright © 2026 Mac Tidy contributors and the credited Mole authors. You may modify and redistribute this software under GNU GPL v3. It comes with no warranty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Mac Tidy is independent from and not endorsed by the Mole project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Mole Engine Source", destination: URL(string: "https://github.com/tw93/Mole")!)
            }

            MoleCard(
                title: "Full Disk Access",
                subtitle: "Manage access used for complete storage scans and cleanup."
            ) {
                HStack {
                    Button {
                        FullDiskAccessSetup.openSettings()
                    } label: {
                        Label("Open Full Disk Access Settings", systemImage: "gearshape")
                    }
                    .standardButton()

                    Button {
                        FullDiskAccessSetup.revealApplication()
                    } label: {
                        Label("Show Mac Tidy in Finder", systemImage: "finder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                Text("macOS requires manual approval and does not allow applications or installers to grant this permission automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SafetyNote(text: "Cleanup selection happens here. Mole still owns scanning, path protection, identity checks, mutations, and operation logs.")
        }
    }
}

struct WhitelistEditorView: View {
    @EnvironmentObject private var runner: MoleRunner
    @Environment(\.dismiss) private var dismiss
    let mode: WhitelistMode

    @State private var selected = Set<String>()
    @State private var customPatterns: [String] = []
    @State private var newPattern = ""
    @State private var loadedCatalog: WhitelistCatalog?

    private var catalog: WhitelistCatalog? { runner.whitelistCatalog(for: mode) }

    private var categories: [String] {
        Array(Set(catalog?.items.map(\.category) ?? [])).sorted()
    }

    var body: some View {
        NavigationStack {
            Group {
                if let catalog {
                    List {
                        Section {
                            Text("Selected items remain protected. Mandatory safety protections always stay active.")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(categories, id: \.self) { category in
                            Section(categoryTitle(category)) {
                                ForEach(catalog.items.filter { $0.category == category }) { item in
                                    Button {
                                        toggle(item.pattern)
                                    } label: {
                                        HStack {
                                            Image(systemName: selected.contains(item.pattern) ? "checkmark.square.fill" : "square")
                                                .foregroundStyle(selected.contains(item.pattern) ? .green : .secondary)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.name)
                                                    .foregroundStyle(.primary)
                                                Text(item.pattern)
                                                    .font(.caption.monospaced())
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Section("Custom patterns") {
                            ForEach(customPatterns, id: \.self) { pattern in
                                HStack {
                                    Text(pattern)
                                        .font(.body.monospaced())
                                    Spacer()
                                    Button {
                                        customPatterns.removeAll { $0 == pattern }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove pattern")
                                }
                            }
                            HStack {
                                TextField("Path or task pattern", text: $newPattern)
                                Button {
                                    addCustomPattern()
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .disabled(normalizedNewPattern == nil)
                                .help("Add pattern")
                            }
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        if runner.isRunning {
                            ProgressView()
                            Text("Loading protections…")
                        } else {
                            Text("Protections could not be loaded.")
                            Button("Retry") { runner.refreshWhitelist(mode) }
                        }
                        Text(runner.presentedError ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let patterns = Array(selected).sorted() + customPatterns
                        runner.saveWhitelist(mode, patterns: patterns) { succeeded in
                            if succeeded { dismiss() }
                        }
                    }
                    .disabled(loadedCatalog == nil || runner.isRunning)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 620)
        .onAppear {
            runner.refreshWhitelist(mode)
        }
        .onChange(of: catalog, initial: true) { _, updated in
            guard let updated, updated != loadedCatalog else { return }
            loadedCatalog = updated
            selected = Set(updated.items.filter(\.selected).map(\.pattern))
            customPatterns = updated.customPatterns
        }
    }

    private var normalizedNewPattern: String? {
        let value = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\n"), !value.contains("\r") else { return nil }
        guard !customPatterns.contains(value), !selected.contains(value) else { return nil }
        return value
    }

    private func addCustomPattern() {
        guard let value = normalizedNewPattern else { return }
        customPatterns.append(value)
        newPattern = ""
    }

    private func toggle(_ pattern: String) {
        if selected.contains(pattern) {
            selected.remove(pattern)
        } else {
            selected.insert(pattern)
        }
    }

    private func categoryTitle(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
