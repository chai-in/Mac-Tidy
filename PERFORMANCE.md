# Mac Tidy 1.0.2 performance

Measured on the same Apple silicon Mac using release-optimized benchmark
code and disposable local files. These figures describe the listed workloads,
not a universal reduction in the app's total resource use.

| Workload | Before | After | Change |
| --- | ---: | ---: | --- |
| 16 MiB activity capture, process peak RSS | 547.8 MB | 11.2 MB | 98.0% lower |
| 16 MiB activity capture, elapsed time | 0.905 s | 0.212 s | 76.6% lower |
| Six status updates at a nominal five-second interval, CPU time | 7.886 s | 2.025 s | 74.3% lower |
| 1,000-file analysis, median of four runs | 0.320 s | 0.081 s | 74.7% lower |

The activity workload generates 16 MiB from a child process and measures the
native runner without a visible SwiftUI window. The status comparison uses
six complete displayed snapshots: repeated shell/Go invocations versus one
warm Go watch collector. Both spans were about 27 seconds. The analysis
comparison uses the same disposable directory through the CLI wrapper and
the directly bundled analyzer.

## Changes

- Activity buffers retain at most 128 KiB per stream. Older text is marked as
  omitted; the engine's operation-history behavior is unchanged.
- Progress uses readiness-based pipe reads, one pending UI update per 100 ms,
  and a dedicated observable object, so logging does not redraw every screen.
- JSON results stay as bytes through decoding. A 32 MiB limit fails closed
  instead of accepting a truncated scan plan.
- Status auto-refresh uses the engine's existing watch collector. It stops
  when the Status screen or app becomes inactive, on another action, or on quit.
  Slow-changing fields follow the existing 30-second enrichment cadence.
- Partial collection errors travel with the corresponding status record and
  are not presented as complete healthy snapshots.
- Result lists sort once per render; analysis creates rows lazily.
- Release builds use size optimization and strip local symbols. Icons render
  at exact pixel dimensions. ZIP compression is lossless at level nine.

The client and bundled engine communicate through local process pipes.
There is no remote application server to optimize. Routine status and
analysis do not use an application HTTP API; this work does not claim a
measured reduction in system-wide internet traffic. Smaller release archives
reduce app-download transfer size. Deleting caches can cause other apps to
download their data again, so cleanup protections remain unchanged.

## Reproduce and verify

`scripts/benchmark-runner.sh` prints activity-capture timing, peak RSS,
retained output, and success as JSON. For backend measurements, compare
`mole status --json` with `status-go --watch --interval 5s`, and
`mole analyze --json <fixture>` with `analyze-go --json <fixture>`.
Use disposable data and the same sampling count and machine conditions.

Regression checks cover buffer bounds, preserved diagnostics, Unicode
framing, JSON overflow refusal, live progress, monitor cancellation,
foreground-action coordination, and incomplete status records.
