#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
BENCHMARK_DIR="$(mktemp -d /tmp/mac-tidy-runner-bench.XXXXXX)"
cleanup() {
    case "$BENCHMARK_DIR" in
        /tmp/mac-tidy-runner-bench.*) rm -rf -- "$BENCHMARK_DIR" ;; # SAFE: only this invocation's temporary build.
    esac
}
trap cleanup EXIT

sources=()
for name in Models ProcessOutput MoleStatusStream MoleRunner; do
    source_file="$PROJECT_DIR/Sources/MacTidy/$name.swift"
    [[ ! -f "$source_file" ]] || sources+=("$source_file")
done
swiftc -O -parse-as-library "${sources[@]}" "$PROJECT_DIR/scripts/benchmarks/RunnerBenchmark.swift" -o "$BENCHMARK_DIR/runner"
"$BENCHMARK_DIR/runner"
