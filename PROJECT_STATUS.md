# Mac Tidy project status

## Product

- Native macOS maintenance GUI with a bundled engine.
- Application version: `1.0.0`.
- Bundle identifier: `com.chai.mactidy`.
- Deployment target: macOS 14 or later.
- Builds support Apple silicon only (`arm64`).

## Bundled engine

- Mole version: `V1.53.0`.
- Upstream commit: `1b9023b5f151c2d963bbcb9cb658f4824137b8aa`.
- Complete vendored source and Mac Tidy modifications live in `Vendor/Mole`.
- `Vendor/Mole/MODIFICATIONS.md` records the native bridge changes.

## Safety invariants

- Preview commands never receive mutation authorization.
- Every mutation requires native confirmation and engine-side confirmation.
- Uninstall, project purge, installer removal, and analyzer Trash actions pass
  exact selections to the engine.
- The engine revalidates protected paths and stale selections before changes.
- Packaged apps only execute their signed, bundled engine.
- Development engine fallback is available only outside an app bundle.

## Full Disk Access

macOS does not allow an app or installer to grant Full Disk Access. On first
open, Mac Tidy explains the permission and opens the correct Privacy & Security
page. The user must approve access there. Limited-access use remains available.

## Distribution

`scripts/build-app.sh` produces an Apple silicon app ZIP, DMG, and corresponding
source ZIP in `dist`. It runs Swift and Go tests, builds `arm64` executables,
embeds license and modification notices, signs the local preview ad hoc,
verifies the bundle and archives, and smoke-tests the packaged engine.

Local artifacts remain explicitly named `unnotarized`. A public binary release
still requires an Apple Developer ID certificate and notarization credentials.
Source publication does not require those Apple credentials.
