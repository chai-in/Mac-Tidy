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

Local artifacts remain explicitly named `unnotarized`. Developer ID signing
and Apple notarization require an Apple Developer ID certificate and
notarization credentials. Source publication does not require those credentials.

## Verification on 2026-09-05

- The native app passed 22 Swift tests, including large-file decoding,
  confirmation isolation, uncertain purge selection, and process-tree cancellation.
- All three Go packages passed their tests.
- The full 1,750-case upstream shell run completed with six failures under
  load. Each failed case passed focused reruns; the affected failures concerned
  timing or host-dependent probes. No test thresholds were relaxed.
- Twelve focused shell tests passed for native confirmation, preview scope,
  and administrator prompt routing using mocked authorization.
- Packaged bridge smoke checks passed on disposable data, including configuration
  save/reload, denied unconfirmed mutations, previews, exact project and installer
  removals, preserved unselected files, and JSON decoding.
- Apple silicon builds and minimum macOS versions passed inspection. The
  ad-hoc signature and DMG checksums passed validation.
- The source archive includes Go dependency sources and license notices; its
  analyzer rebuilt with network access disabled and an empty module cache.
- Native window checks confirmed first-open guidance, the dashboard, existing
  cleanup protections after reopening the editor, folder analysis, and a
  128 MiB large-file result.
- GitHub CI checks the native app, Go packages, native confirmation and prompt
  routing, and the disposable bridge smoke flows on each push.

No real administrator-protected changes or cleanup of the user's files were
run. No Developer ID signing identity was available in the local keychain.
