import AppKit
import Darwin
import Foundation

@main
struct RunnerBenchmark {
    @MainActor
    static func main() async {
        let runner = MoleRunner(executablePath: "/usr/bin/python3")
        let started = Date()
        let result: CommandResult = await withCheckedContinuation { continuation in
            runner.runCapture(MoleInvocation(label: "Output benchmark", arguments: [
                "-c", "import sys; sys.stdout.write('x' * (16 * 1024 * 1024)); print('END-MARKER')"
            ], risk: .readOnly)) { result in continuation.resume(returning: result) }
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("{\"seconds\":\(Date().timeIntervalSince(started)),\"peak_rss_bytes\":\(usage.ru_maxrss),\"retained_stdout_bytes\":\(result.standardOutput.utf8.count),\"activity_bytes\":\(runner.activity.utf8.count),\"succeeded\":\(result.succeeded)}")
    }
}
