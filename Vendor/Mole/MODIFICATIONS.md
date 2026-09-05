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

These changes are distributed under GNU GPL v3 only. Mac Tidy is independent
from and not endorsed by the Mole project. See `TRADEMARK.md`.
