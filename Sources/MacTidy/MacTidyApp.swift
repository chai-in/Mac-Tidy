import AppKit
import Combine
import SwiftUI

@main
struct MacTidyApp: App {
    @NSApplicationDelegateAdaptor(MacTidyAppDelegate.self) private var appDelegate
    @StateObject private var runner = MoleRunner()

    var body: some Scene {
        Window("Mac Tidy", id: "main") {
            ContentView()
                .environmentObject(runner)
                .tint(.green)
                .onAppear { appDelegate.runner = runner }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_180, height: 760)
    }
}

@MainActor
final class MacTidyAppDelegate: NSObject, NSApplicationDelegate {
    weak var runner: MoleRunner?
    private var terminationObserver: AnyCancellable?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        runner?.stopStatusMonitoring()
        guard let runner, runner.isRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Stop the current task and quit?"
        alert.informativeText = "Mac Tidy will stop the running operation before quitting. Changes already completed are not undone."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Stop and Quit")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }

        terminationObserver = runner.$isRunning
            .filter { !$0 }
            .prefix(1)
            .receive(on: DispatchQueue.main)
            .sink { _ in sender.reply(toApplicationShouldTerminate: true) }
        runner.cancel()
        return .terminateLater
    }
}
