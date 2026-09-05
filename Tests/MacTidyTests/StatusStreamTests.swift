import Darwin
import Combine
import Foundation
import XCTest
@testable import MacTidy

final class StatusStreamTests: XCTestCase {
    func testLineFramingHandlesSplitUnicodeAndMultipleRecords() throws {
        var buffer = JSONLineBuffer()
        let payload = Data("{\"name\":\"café\"}\n{\"value\":2}\n".utf8)
        var frames: [Data] = []
        for byte in payload { frames += try buffer.append(Data([byte])) }
        XCTAssertEqual(frames.map { String(decoding: $0, as: UTF8.self) }, [#"{"name":"café"}"#, #"{"value":2}"#])
    }

    func testLineFramingRejectsAnUnterminatedOversizedRecord() throws {
        var buffer = JSONLineBuffer(maximumBytes: 8)
        XCTAssertTrue(try buffer.append(Data(repeating: 120, count: 8)).isEmpty)
        XCTAssertThrowsError(try buffer.append(Data([120])))
    }

    func testBundledHelpersKeepArgumentsAndNeverFallBackToAnotherInstallation() {
        let target = MoleExecutableLocator.launchTarget(
            for: MoleCommands.analyzeJSON(path: "/tmp/Folder With Spaces"),
            enginePath: "/Applications/Mac Tidy.app/Contents/Resources/Mole/mole", bundled: true)
        XCTAssertEqual(target.url.path, "/Applications/Mac Tidy.app/Contents/Resources/Mole/bin/analyze-go")
        XCTAssertEqual(target.arguments, ["--json", "/tmp/Folder With Spaces"])
        let development = MoleExecutableLocator.launchTarget(for: MoleCommands.statusJSON, enginePath: "/tmp/fake-engine", bundled: false)
        XCTAssertEqual(development.url.path, "/tmp/fake-engine")
        XCTAssertEqual(development.arguments, ["status", "--json"])
        let trash = MoleExecutableLocator.launchTarget(for: MoleCommands.moveToTrash(paths: ["/tmp/item"]), enginePath: "/bundle/Mole/mole", bundled: true)
        XCTAssertEqual(trash.arguments, ["--trash-json", "/tmp/item"])
        XCTAssertEqual(MoleCommands.moveToTrash(paths: ["/tmp/item"]).environment["MOLE_GUI_CONFIRMED"], "1")
    }

    func testStreamCancellationStopsItsProcess() async throws {
        let stream = MoleStatusStream()
        let frames = stream.start(url: URL(fileURLWithPath: "/bin/bash"),
                                  arguments: ["-c", "printf '%s\\n' \"$$\"; exec sleep 30"],
                                  environment: ProcessInfo.processInfo.environment)
        var iterator = frames.makeAsyncIterator()
        let next = try await iterator.next()
        let data = try XCTUnwrap(next)
        let pid = try XCTUnwrap(Int32(String(decoding: data, as: UTF8.self)))
        stream.cancel()
        for _ in 0..<40 where kill(pid, 0) == 0 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotEqual(kill(pid, 0), 0)
    }

    @MainActor
    func testRunnerUsesCompleteSnapshotsAndStopsMonitoringBeforeAnAction() async throws {
        let fixture = try makeFixture(error: false)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let runner = MoleRunner(executablePath: fixture.script.path)
        let received = expectation(description: "Complete status snapshot received")
        let observation = runner.$status.first(where: { $0?.healthScore == 70 }).sink { _ in received.fulfill() }
        let task = Task { await runner.monitorStatus() }
        defer { task.cancel(); runner.stopStatusMonitoring() }
        await fulfillment(of: [received], timeout: 4)
        XCTAssertEqual(runner.status?.healthScore, 70)
        XCTAssertFalse(runner.isRunning)
        let pid = try XCTUnwrap(Int32(String(contentsOf: fixture.directory.appendingPathComponent("pid")).trimmingCharacters(in: .whitespacesAndNewlines)))

        let finished = expectation(description: "Foreground action completed")
        runner.runCapture(MoleCommands.version, showActivity: false) { result in
            XCTAssertTrue(result.succeeded)
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 4)
        await task.value
        for _ in 0..<20 where kill(pid, 0) == 0 { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertNotEqual(kill(pid, 0), 0)
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testPartialCollectionIsNotPublishedAsHealthy() async throws {
        let fixture = try makeFixture(error: true)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let runner = MoleRunner(executablePath: fixture.script.path)
        let failed = expectation(description: "Collection error shown")
        let observation = runner.$presentedError.first(where: { $0?.contains("disk query failed") == true }).sink { _ in failed.fulfill() }
        let task = Task { await runner.monitorStatus() }
        defer { task.cancel(); runner.stopStatusMonitoring() }
        await fulfillment(of: [failed], timeout: 4)
        XCTAssertNil(runner.status)
        withExtendedLifetime(observation) {}
    }

    private func makeFixture(error: Bool) throws -> (directory: URL, script: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("engine")
        let fast = #"{"host":"fixture","uptime":"1h","health_score":99,"cpu":{"usage":1},"memory":{"used":100,"total":200,"used_percent":50},"disks":[],"hardware":{}}"#
        let full = #"{"host":"fixture","uptime":"1h","health_score":70,"cpu":{"usage":1},"memory":{"used":100,"total":200,"used_percent":50},"disks":[],"hardware":{"total_ram":"200 B"}}"#
        let failed = #"{"host":"fixture","uptime":"1h","health_score":99,"collection_error":"disk query failed","cpu":{"usage":0},"memory":{"used":0,"total":0,"used_percent":0},"disks":[],"hardware":{}}"#
        let records = error ? "'\(failed)'" : "'\(fast)' '\(full)'"
        try """
        #!/bin/bash
        if [[ "$1" == status ]]; then
            echo "$$" > '\(directory.path)/pid'
            printf '%s\\n' \(records)
            exec sleep 30
        fi
        echo 'Mole version 1.53.0'
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (directory, script)
    }
}
