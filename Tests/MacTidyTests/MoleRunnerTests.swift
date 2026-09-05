import Darwin
import Foundation
import XCTest
@testable import MacTidy

final class MoleRunnerTests: XCTestCase {
    func testPreviewDropsInheritedMutationAuthorizationAndBridgeState() {
        let preview = MoleCommands.clean(preview: true, externalPath: nil, debug: false, includeSystemCaches: false)
        let environment = MoleRunner.commandEnvironment(invocation: preview, inherited: [
            "HOME": "/Users/example",
            "MOLE_GUI_CONFIRMED": "1",
            "MOLE_GUI_PURGE_MODE": "remove",
            "BASH_ENV": "/tmp/injected.sh",
            "ENV": "/tmp/injected.sh"
        ])
        XCTAssertNil(environment["MOLE_GUI_CONFIRMED"])
        XCTAssertNil(environment["MOLE_GUI_PURGE_MODE"])
        XCTAssertNil(environment["BASH_ENV"])
        XCTAssertNil(environment["ENV"])
        XCTAssertEqual(environment["MOLE_GUI_SYSTEM_CACHES"], "skip")
        XCTAssertEqual(environment["MOLE_GUI_MODE"], "1")
        XCTAssertEqual(environment["HOME"], "/Users/example")
    }

    func testConfirmedMutationGetsOnlyItsOwnBridgeState() {
        let command = MoleCommands.moveToTrash(paths: ["/tmp/disposable"])
        let environment = MoleRunner.commandEnvironment(invocation: command, inherited: [
            "MOLE_GUI_SYSTEM_CACHES": "include"
        ])
        XCTAssertEqual(environment["MOLE_GUI_CONFIRMED"], "1")
        XCTAssertNil(environment["MOLE_GUI_SYSTEM_CACHES"])
    }

    func testPurgeRecommendationExcludesEveryUncertainCandidate() {
        for recent in [false, true] {
            for cloud in [false, true] {
                for unknown in [false, true] {
                    let item = PurgeCandidate(
                        path: "/tmp/project/.build", displayPath: "/tmp/project/.build",
                        projectPath: "/tmp/project", artifact: ".build", sizeKb: 0,
                        sizeUnknown: unknown, recent: recent, age: "30d", cloud: cloud
                    )
                    if recent || cloud || unknown {
                        XCTAssertFalse(item.recommended)
                    } else {
                        XCTAssertTrue(item.recommended)
                    }
                }
            }
        }
    }

    @MainActor
    func testRunnerCapturesBothStreamsAndExitFailure() async {
        let runner = MoleRunner(executablePath: "/bin/bash")
        let finished = expectation(description: "Command exited")
        runner.runCapture(MoleInvocation(label: "Fixture", arguments: ["-c", "printf 'output'; printf 'diagnostic' >&2; exit 7"], risk: .readOnly), recordActivity: false) { result in
            XCTAssertEqual(result.standardOutput, "output")
            XCTAssertEqual(result.standardError, "diagnostic")
            XCTAssertEqual(result.exitCode, 7)
            XCTAssertFalse(result.succeeded)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertFalse(runner.isRunning)
        XCTAssertFalse(runner.showsActivity, "Background failures must not open the output panel")
        XCTAssertTrue(runner.activity.contains("diagnostic"))
        XCTAssertEqual(runner.presentedError, "Fixture failed: diagnostic")
    }

    @MainActor
    func testCompletedActivityOnlyOpensOnRequestAndRemainsAvailableAfterHiding() async {
        let runner = MoleRunner(executablePath: "/bin/bash")
        let finished = expectation(description: "Hidden command completed")
        runner.runCapture(.init(label: "Preview", arguments: ["-c", "printf 'preview details'"], risk: .preview)) { _ in
            finished.fulfill()
        }
        XCTAssertFalse(runner.showsActivity, "Starting a command must not open the panel")
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertFalse(runner.showsActivity, "Finishing a command must not open the panel")
        XCTAssertTrue(runner.activity.contains("preview details"))

        runner.toggleActivity()
        XCTAssertTrue(runner.showsActivity)
        runner.toggleActivity()
        XCTAssertFalse(runner.showsActivity)
        XCTAssertTrue(runner.activity.contains("preview details"), "Hiding the panel must preserve its output")
    }

    @MainActor
    func testFailureAlertUsesTheDiagnosticInsteadOfTheCommandHeading() async {
        let runner = MoleRunner(executablePath: "/bin/bash")
        let finished = expectation(description: "Preview failure captured")
        runner.runCapture(MoleInvocation(label: "Preview optimization", arguments: [
            "-c", "printf 'Optimize\\n\\nDry run mode\\n  ◎ Failed to scan shared file lists\\nSummary: 1 failed\\n'; exit 1"
        ], risk: .preview)) { _ in finished.fulfill() }
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertFalse(runner.showsActivity, "Preview failures must not open the output panel")
        XCTAssertTrue(runner.presentedError?.contains("Failed to scan shared file lists") == true)
        XCTAssertFalse(runner.presentedError?.contains("failed: Optimize") == true)
    }

    @MainActor
    func testFailureWithoutDiagnosticReportsExitCodeAndActivity() async {
        let runner = MoleRunner(executablePath: "/bin/bash")
        let finished = expectation(description: "Unexplained failure captured")
        runner.runCapture(MoleInvocation(label: "Fixture", arguments: [
            "-c", "printf 'Optimize\\n'; exit 9"
        ], risk: .preview)) { _ in finished.fulfill() }
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(runner.presentedError, "Fixture failed with exit code 9. See Activity for details.")
    }

    @MainActor
    func testCancellationStopsTermIgnoringChildAndPreservesOutput() async throws {
        try await checkCancellation(script: "trap '' TERM; sleep 30 & child=$!; printf '%s\\n' \"$child\"; wait \"$child\"")
    }

    @MainActor
    func testCancellationStopsChildAfterItsParentHasExited() async throws {
        try await checkCancellation(script: "/bin/bash -c 'trap \"\" TERM; sleep 30' & child=$!; printf '%s\\n' \"$child\"; wait \"$child\"")
    }

    @MainActor
    private func checkCancellation(script: String) async throws {
        let runner = MoleRunner(executablePath: "/bin/bash")
        let finished = expectation(description: "Cancelled process and child exited")
        var childPID: pid_t?
        runner.runCapture(MoleInvocation(label: "Cancellation fixture", arguments: [
            "-c", script
        ], risk: .readOnly)) { result in
            childPID = Int32(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))
            XCTAssertTrue(result.cancelled)
            XCTAssertFalse(result.succeeded)
            finished.fulfill()
        }
        try await Task.sleep(nanoseconds: 250_000_000)
        runner.cancel()
        await fulfillment(of: [finished], timeout: 8)
        XCTAssertFalse(runner.isRunning)
        XCTAssertFalse(runner.showsActivity, "Cancellation must not open the output panel")
        XCTAssertTrue(runner.activity.contains("Stopped."))
        let pid = try XCTUnwrap(childPID)
        for _ in 0..<20 where kill(pid, 0) == 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotEqual(kill(pid, 0), 0, "Child must not continue after Stop completes")
    }
}
