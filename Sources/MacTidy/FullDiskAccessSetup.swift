import AppKit
import SwiftUI

enum FullDiskAccessSetup {
    static var currentVersion: String { AppMetadata.version }

    static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
    )!

    static func shouldPresent(completedVersion: String) -> Bool {
        completedVersion != currentVersion
    }

    @MainActor
    static func openSettings() {
        NSWorkspace.shared.open(settingsURL)
    }

    @MainActor
    static func revealApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

struct FullDiskAccessSetupView: View {
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 56, height: 56)
                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Allow Full Disk Access")
                        .font(.largeTitle.bold())
                    Text("Required for complete storage scans and cleanup")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            Text("macOS requires you to approve this access manually. Without it, Mac Tidy still works but cannot inspect some protected caches, logs, application data, Mail, Messages, or browser storage.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                setupStep(1, "Keep Mac Tidy in Applications before granting access.")
                setupStep(2, "Open Full Disk Access settings and enable Mac Tidy. If it is not listed, use the add button and choose this application.")
                setupStep(3, "Return here, then continue.")
            }
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

            HStack {
                Button {
                    FullDiskAccessSetup.revealApplication()
                } label: {
                    Label("Show Mac Tidy in Finder", systemImage: "finder")
                }
                .standardButton()

                Button {
                    FullDiskAccessSetup.openSettings()
                } label: {
                    Label("Open Full Disk Access Settings", systemImage: "gearshape")
                }
                .primaryButton()
            }

            Divider()

            HStack {
                Text("You can reopen these settings later from About.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Continue") {
                    finish()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 680)
        .interactiveDismissDisabled()
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.green, in: Circle())
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
