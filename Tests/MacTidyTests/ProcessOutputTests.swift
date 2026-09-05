import Combine
import Foundation
import XCTest
@testable import MacTidy

final class ProcessOutputTests: XCTestCase {
    func testTextOutputStaysBoundedAndRetainsEarlyFailure() {
        let capture = ProcessOutputCapture(format: .text, displayEnabled: true)
        XCTAssertTrue(capture.append(Data("Error: initial failure\n".utf8), isError: false))
        let chunk = Data(repeating: 120, count: 8_192)
        for _ in 0..<512 {
            XCTAssertFalse(capture.append(chunk, isError: false))
        }
        _ = capture.append(Data("\nEND-MARKER\n".utf8), isError: false)
        let result = capture.snapshot(finishing: true)
        XCTAssertLessThanOrEqual(result.stdout.count, ProcessOutputCapture.textLimit)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.diagnostic, "Error: initial failure")
        XCTAssertTrue(String(decoding: result.stdout, as: UTF8.self).hasSuffix("END-MARKER\n"))
        XCTAssertNil(result.error)
    }

    func testOversizedJSONFailsInsteadOfBecomingAPartialResult() {
        let capture = ProcessOutputCapture(format: .json, displayEnabled: false, jsonLimit: 64)
        _ = capture.append(Data(repeating: 32, count: 60), isError: false)
        _ = capture.append(Data(repeating: 32, count: 10), isError: false)
        let snapshot = capture.snapshot(finishing: true)
        XCTAssertLessThanOrEqual(snapshot.stdout.count, 64)
        XCTAssertNotNil(snapshot.error)
        let result = CommandResult(invocation: .init(label: "Scan", arguments: [], risk: .readOnly),
                                   standardOutputData: snapshot.stdout, standardErrorData: snapshot.stderr,
                                   exitCode: 0, cancelled: false, outputError: snapshot.error)
        XCTAssertFalse(result.succeeded)
    }

    func testJSONBytesSurviveChunkBoundariesWithoutTextRoundTrip() throws {
        let capture = ProcessOutputCapture(format: .json, displayEnabled: false)
        let input = Data(#"{"name":"café 🐕","path":"/tmp/folder"}"#.utf8)
        for byte in input { _ = capture.append(Data([byte]), isError: false) }
        let snapshot = capture.snapshot(finishing: true)
        XCTAssertEqual(snapshot.stdout, input)
        XCTAssertNil(snapshot.error)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: snapshot.stdout) as? [String: String],
                       ["name": "café 🐕", "path": "/tmp/folder"])
    }

    func testDisplayNotificationsCoalesceAndPauseWhileHidden() {
        let capture = ProcessOutputCapture(format: .text, displayEnabled: true)
        XCTAssertTrue(capture.append(Data("one".utf8), isError: false))
        XCTAssertFalse(capture.append(Data("two".utf8), isError: true))
        _ = capture.snapshot(consumingUpdate: true)
        XCTAssertTrue(capture.append(Data("three".utf8), isError: false))
        _ = capture.snapshot(consumingUpdate: true)
        capture.setDisplayEnabled(false)
        XCTAssertFalse(capture.append(Data("hidden".utf8), isError: false))
    }

    func testConsoleEscapeRemovalAndBoundedDisplay() {
        XCTAssertEqual(ConsoleOutput.clean("\u{001B}[31mred\u{001B}[0m\r\n"), "red")
        XCTAssertEqual(ConsoleOutput.clean("\u{001B}]0;window\u{0007}body"), "body")
        let output = ConsoleOutput.display(stdout: Data(repeating: 120, count: 1_000_000), stderr: Data(), truncated: false)
        XCTAssertTrue(output.hasPrefix("Earlier activity omitted"))
        XCTAssertLessThan(output.utf8.count, ConsoleOutput.displayLimit + 200)
    }

    @MainActor
    func testActivityUpdatesDoNotInvalidateTheWholeRunner() async {
        let runner = MoleRunner(executablePath: "/bin/bash")
        var runnerChanges = 0
        var activityChanges = 0
        let whole = runner.objectWillChange.sink { runnerChanges += 1 }
        let panel = runner.activityState.objectWillChange.sink { activityChanges += 1 }
        runner.activityState.text = "visible progress"
        XCTAssertEqual(runnerChanges, 0)
        XCTAssertEqual(activityChanges, 1)
        withExtendedLifetime((whole, panel)) {}
    }

    @MainActor
    func testSmallProgressIsVisibleBeforeTheChildExits() async throws {
        let runner = MoleRunner(executablePath: "/bin/bash")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            runner.cancel()
            try? FileManager.default.removeItem(at: directory)
        }
        let release = directory.appendingPathComponent("release")
        let progress = expectation(description: "Small progress delivered")
        let done = expectation(description: "Process completed")
        let observation = runner.activityState.$text.first(where: { $0.contains("ready") }).sink { _ in progress.fulfill() }
        runner.runCapture(.init(label: "Progress", arguments: [
            "-c", "printf 'ready\\n'; while [ ! -f \"$1\" ]; do sleep 0.02; done; printf 'done\\n'", "_", release.path
        ], risk: .readOnly)) { _ in
            done.fulfill()
        }
        await fulfillment(of: [progress], timeout: 3)
        XCTAssertTrue(runner.isRunning)
        XCTAssertTrue(runner.activity.contains("ready"))
        try Data().write(to: release)
        await fulfillment(of: [done], timeout: 4)
        withExtendedLifetime(observation) {}
    }
}
