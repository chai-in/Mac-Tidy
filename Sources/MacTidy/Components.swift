import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var runner: MoleRunner
    @AppStorage("fullDiskAccessSetupVersion") private var fullDiskAccessSetupVersion = ""
    @State private var selection: MoleFeature? = .overview
    @State private var showsFullDiskAccessSetup = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Toolkit") {
                    featureRows(MoleFeature.toolkit)
                }
                Section("Storage") {
                    featureRows(MoleFeature.storage)
                }
                Section("Settings") {
                    featureRows(MoleFeature.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom) {
                engineBadge
            }
        } detail: {
            VStack(spacing: 0) {
                featureView(selection ?? .overview)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if runner.showsActivity {
                    Divider()
                    ActivityPanel(activityState: runner.activityState)
                        .frame(minHeight: 150, idealHeight: 210, maxHeight: 280)
                }

                Divider()
                HStack {
                    Button {
                        runner.toggleActivity()
                    } label: {
                        Label(runner.showsActivity ? "Hide Activity" : "Show Activity",
                              systemImage: runner.showsActivity ? "chevron.down" : "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(runner.showsActivity ? "Expanded" : "Collapsed")
                    Spacer()
                    if !runner.isRunning && runner.lastExitCode != nil {
                        Text("Activity available")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.bar)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .toolbar {
                ToolbarItem {
                    if runner.isRunning {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(runner.activeLabel ?? "Working…")
                                .font(.caption)
                            Button("Stop") { runner.cancel() }
                                .disabled(runner.cancelRequested)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 940, minHeight: 660)
        .task {
            runner.bootstrap()
            if FullDiskAccessSetup.shouldPresent(completedVersion: fullDiskAccessSetupVersion) {
                showsFullDiskAccessSetup = true
            }
        }
        .sheet(isPresented: $showsFullDiskAccessSetup) {
            FullDiskAccessSetupView {
                fullDiskAccessSetupVersion = FullDiskAccessSetup.currentVersion
                showsFullDiskAccessSetup = false
            }
        }
        .alert("Mac Tidy", isPresented: Binding(
            get: { runner.presentedError != nil },
            set: { if !$0 { runner.presentedError = nil } }
        )) {
            Button("OK") { runner.presentedError = nil }
        } message: {
            Text(runner.presentedError ?? "")
        }
    }

    @ViewBuilder
    private func featureRows(_ features: [MoleFeature]) -> some View {
        ForEach(features) { feature in
            Label(feature.title, systemImage: feature.icon)
                .tag(feature)
        }
    }

    @ViewBuilder
    private func featureView(_ feature: MoleFeature) -> some View {
        switch feature {
        case .overview: OverviewView(selection: $selection)
        case .clean: CleanView()
        case .uninstall: UninstallView()
        case .optimize: OptimizeView()
        case .analyze: AnalyzeView()
        case .status: StatusView()
        case .history: HistoryView()
        case .purge: PurgeView()
        case .installers: InstallersView()
        case .touchID: TouchIDView()
        case .about: AboutView()
        }
    }

    private var engineBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(runner.isAvailable ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(runner.isAvailable ? "Mole \(runner.moleVersion)" : "Engine unavailable")
                    .font(.caption.weight(.semibold))
                Text(runner.isAvailable
                     ? (runner.usesBundledEngine ? "Bundled engine" : "Development engine")
                     : "Reinstall Mac Tidy")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct FeaturePage<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.green)
                        .frame(width: 48, height: 48)
                        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.largeTitle.bold())
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                content()
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct MoleCard<Content: View>: View {
    var title: String?
    var subtitle: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

struct SafetyNote: View {
    let text: String
    var destructive = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: destructive ? "exclamationmark.triangle.fill" : "shield.checkered")
                .foregroundStyle(destructive ? .orange : .green)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((destructive ? Color.orange : Color.green).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct FolderField: View {
    @Binding var path: String
    var prompt = "Choose folder"
    var startAtVolumes = false

    var body: some View {
        HStack {
            TextField(prompt, text: $path)
                .textFieldStyle(.roundedBorder)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Choose"
                if startAtVolumes {
                    panel.directoryURL = URL(fileURLWithPath: "/Volumes")
                } else if FileManager.default.fileExists(atPath: path) {
                    panel.directoryURL = URL(fileURLWithPath: path)
                }
                if panel.runModal() == .OK, let url = panel.url {
                    path = url.path
                }
            }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let progress: Double?
    var color: Color = .green

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold().monospacedDigit())
            if let progress {
                ProgressView(value: min(max(progress, 0), 100), total: 100)
                    .tint(color)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

struct ActivityPanel: View {
    @EnvironmentObject private var runner: MoleRunner
    @ObservedObject var activityState: MoleActivity

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if runner.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Text(runner.activeLabel ?? "Working")
                        .font(.caption.weight(.semibold))
                } else {
                    Image(systemName: runner.lastOutputError != nil ? "exclamationmark.triangle" : (runner.lastExitCode == 0 ? "checkmark.circle.fill" : "list.bullet.rectangle"))
                        .foregroundStyle(runner.lastOutputError != nil ? .orange : (runner.lastExitCode == 0 ? .green : .secondary))
                    Text(runner.lastOutputError != nil ? "Result unavailable" : (runner.lastExitCode.map { $0 == 0 ? "Finished" : "Stopped with code \($0)" } ?? "Activity"))
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                if runner.isRunning {
                    Button("Stop") { runner.cancel() }
                        .controlSize(.small)
                        .disabled(runner.cancelRequested)
                }
                Button {
                    runner.copyActivity()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .disabled(activityState.text.isEmpty)
                .help("Copy activity")
                Button {
                    runner.toggleActivity()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close activity")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.bar)

            ScrollView([.vertical, .horizontal]) {
                Text(activityState.text.isEmpty ? "No activity yet." : activityState.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

extension View {
    func standardButton() -> some View {
        buttonStyle(.bordered)
            .controlSize(.large)
    }

    func primaryButton() -> some View {
        buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}
