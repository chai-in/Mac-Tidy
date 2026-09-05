# Contributing to Mac Tidy

Thanks for improving Mac Tidy. Contributions are accepted under
GPL-3.0-only, the project's existing license.

## Development

Mac Tidy requires macOS 14 or later, Xcode with Swift 5.10 or later, and Go
1.25 or later.

Before opening a pull request, run:

```bash
swift test
GOCACHE=/tmp/mac-tidy-go-cache go test ./...
```

Run the Go command from `Vendor/Mole`. For changes to bundled shell behavior,
also run the focused upstream Bats tests named in `Vendor/Mole/AGENTS.md`.
Packaging changes should pass `./scripts/build-app.sh`.

## Safety requirements

Mac Tidy changes local files and system configuration. Preserve these rules:

- A preview must never receive mutation authorization.
- Every mutation needs a native confirmation and an engine-side confirmation
  check.
- Selected paths must be rebuilt or revalidated immediately before mutation.
- Uncertain, stale, unreadable, or protected paths must fail closed.
- Tests that delete data must use disposable fixtures.

Keep the app's public name and artwork independent from Mole. Retain upstream
copyright, license, modification, and trademark notices.

Describe observable behavior and validation in the pull request. Keep changes
focused and do not include generated builds or local toolchains.
