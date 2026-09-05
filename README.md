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
clearly labeled. Long-running work can be stopped from the Activity panel.

Packaged builds only run their bundled engine. Development builds may use
`MAC_TIDY_EXECUTABLE` or an installed `mo` executable when the bundled engine
is absent.

On first open, Mac Tidy explains why complete scans need Full Disk Access and
opens the correct Privacy & Security page. macOS requires the user to grant
this permission manually. Limited-access use remains available.

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
corresponding-source ZIP in `dist/`.

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
