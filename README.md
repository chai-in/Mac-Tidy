# Mac Tidy

[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0--only-blue.svg)](LICENSE)
[![CI](https://github.com/chai-in/Mac-Tidy/actions/workflows/ci.yml/badge.svg)](https://github.com/chai-in/Mac-Tidy/actions/workflows/ci.yml)

Mac Tidy is an independent, open-source native macOS utility powered by a
modified build of the [Mole](https://github.com/tw93/Mole) maintenance engine.
The engine ships inside the app, so users do not need a separate command-line
installation. Selection, previews, confirmation, progress, cancellation, and
errors stay in standard macOS windows.

## Features

- Clean caches, logs, temporary files, and abandoned application leftovers,
  with a preview and optional external-volume metadata cleanup.
- Review and edit cleanup and optimization protections.
- Uninstall applications by exact path, including related files, using Trash
  by default or explicit permanent removal.
- Preview and apply supported macOS maintenance tasks.
- Analyze folders, inspect large items, reveal them in Finder, and move exact
  selections to Trash.
- View system health, storage, memory, battery, network, and process data.
- Review and export Mole operation history.
- Find and remove selected project build artifacts and installer archives.
- Inspect, preview, enable, or disable Touch ID support for administrator
  authentication.

## Safety

The native app chooses actions and exact selections. The bundled engine owns
scanning, protected-path checks, application identity checks, last-moment path
validation, file operations, and history records.

Read-only scans and previews never receive the app's mutation confirmation
token. Actions that change files require a native confirmation dialog.
Recoverable actions use Trash where Mole supports it; permanent actions are
clearly labeled. Long-running work can be stopped from the toolbar or Activity panel.
Activity output stays hidden until you click **Show Activity** at the bottom.
You can hide it while work continues and reopen it without losing the output.
Starting, completing, cancelling, or failing an action never opens it automatically;
errors still appear in native alerts.

Packaged builds only run their bundled engine. Development builds may use
`MAC_TIDY_EXECUTABLE` or an installed `mo` executable when the bundled engine
is absent.

On first open, Mac Tidy explains why complete scans need Full Disk Access and
opens the correct Privacy & Security page. macOS requires the user to grant
this permission manually. Limited-access use remains available.

## Resource use

Mac Tidy runs locally. Packaged status and analysis requests execute the
bundled Go helpers directly. Automatic status refresh reuses a single warm
collector and pauses when the Status screen is inactive or another task runs.
Hardware and other slow-changing metrics follow the engine's existing refresh
cadence; CPU, memory, network, and process measurements continue to refresh.

Activity is streamed in small batches and retains the latest 128 KiB per
output stream in memory. Earlier text is explicitly marked as omitted, while
the engine's operation history remains available. Structured scan results use
their original JSON bytes with a 32 MiB limit; oversized results fail without
publishing a partial plan. Folder sizes and mutation candidates are still
rescanned and revalidated.

Large result lists sort once per render and load rows as needed. Preview
packages use size-optimized native code, stripped symbols, exact-resolution
icons, and lossless ZIP compression.

See [PERFORMANCE.md](PERFORMANCE.md) for measurements, tradeoffs, and
reproduction steps.

## Build

Requirements:

- Apple silicon Mac running macOS 14 or later
- Xcode with Swift 5.10 or later
- Go 1.25 or later

Run the unit tests:

```bash
swift test
```

Build the verified Apple silicon local preview:

```bash
./scripts/build-app.sh
```

The packaging script tests the Swift and Go code, builds `arm64` binaries,
embeds the engine and license notices, ad-hoc signs the app, verifies
the bundle, smoke-tests the packaged engine, and creates a DMG, app ZIP, and
corresponding-source ZIP in `dist/`. The source ZIP also includes the Go
dependency source needed to rebuild the engine. Checksums are written to
`dist/SHA256SUMS.txt`.

Generated previews are not Developer ID signed or Apple-notarized. macOS may
block the first open. Open **System Settings > Privacy & Security**, find the
blocked Mac Tidy notice, choose **Open Anyway**, then confirm **Open**. Public
binary releases should use Developer ID signing and Apple notarization.

## Provenance and license

Mac Tidy vendors Mole `V1.53.0` from upstream commit
`1b9023b5f151c2d963bbcb9cb658f4824137b8aa`. The native app and modified engine
are distributed under [GNU GPL v3 only](LICENSE). This license is compatible
with the bundled engine and keeps distributed derivatives open source. See
[the engine modification notice](Vendor/Mole/MODIFICATIONS.md) for the
app-specific changes.

Mac Tidy uses its own name and icon. It is not endorsed by or affiliated with
the Mole project. The upstream name identifies the bundled engine only; its
[trademark policy](Vendor/Mole/TRADEMARK.md) remains included.

Contributions are welcome under the same license. Read
[CONTRIBUTING.md](CONTRIBUTING.md) and report security issues through
[SECURITY.md](SECURITY.md).
