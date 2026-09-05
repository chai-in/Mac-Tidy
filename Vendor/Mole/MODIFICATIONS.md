# Modifications for Mac Tidy

Mac Tidy includes a modified copy of Mole V1.53.0, based on upstream commit
`1b9023b5f151c2d963bbcb9cb658f4824137b8aa`.

Mac Tidy contributors changed this copy on 2026-09-04 to provide a
machine-readable bridge for the native application:

- JSON application, cleanup-protection, project-artifact, installer, Touch ID,
  history, status, and disk-analysis flows
- exact-path application uninstall selection
- exact-selection project and installer cleanup
- Finder Trash results for selected analyzer entries
- atomic native editing of cleanup protections and project scan paths
- an engine-side confirmation requirement for native destructive actions
- revalidation of selections at the existing engine safety boundary

On 2026-09-05, the native bridge gained a shared confirmation gate for cleanup,
optimization, and Touch ID changes. Native launches explicitly select GUI
authentication, and cleanup previews honor the app's system-cache exclusion.
CLI callers retain their existing behavior. The native interface also fixes
large-file decoding, cached settings, uncertain purge recommendations, and
process cancellation.

On 2026-09-05, Mac Tidy 1.0.1 corrected the shared-file-list scan to prune
excluded recent-document folders before traversal. Access-denied scans now
report the task as unavailable and discard partial results; genuine errors
and cancellation still propagate. Native alerts now display the diagnostic
rather than a command heading. Regression and full-preview checks cover this fix.

On 2026-09-05, Mac Tidy 1.0.2 added per-record collection errors to the
existing status watch protocol so clients can reject incomplete metrics.
The native app reuses this warm collector, runs bundled status/analyze
helpers directly, bounds output memory, and preserves confirmation and
path-validation behavior.

These changes are distributed under GNU GPL v3 only. Mac Tidy is independent
from and not endorsed by the Mole project. See `TRADEMARK.md`.
