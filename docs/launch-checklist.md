# todo.md v1 Launch Checklist

Last updated: 2026-02-26

## Build and CI

- [x] `swift test` passes locally.
- [x] Simulator build passes (`xcodebuild ... -destination 'generic/platform=iOS Simulator' build`).
- [x] Device build passes (`xcodebuild ... -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`).
- [x] `ci` recipe exists with generate/lint/format-check/test/build-sim/build-device.

## Runtime/Feature

- [x] Filesystem canonical read/write with parser validation.
- [x] Live ingest with conflict and unparseable-file handling.
- [x] Repeating completion creates next instance.
- [x] `.order.json` manual order persistence and conflict LWW handling.
- [x] URL handling, App Intents, share extension integrated.
- [x] Notification schedule and deterministic identifiers.

## Security/Resilience

- [x] Body and field size limits enforced.
- [x] Malformed frontmatter does not crash and is surfaced in diagnostics.
- [x] Burst-ingest detection and user alert path implemented.
- [x] Self-write echo suppression enabled.

## Performance

- [x] Bench runner for `500/1000/5000` tasks exists.
- [x] Latest benchmark artifact path: `docs/benchmarks/latest.json`.
- [x] Runtime telemetry in Diagnostics view (enumerate/parse/index/query ms).

## Release/TestFlight

- [x] Signed archive recipe: `just archive-release` / `make archive-release`.
- [x] IPA export recipe: `just export-ipa` / `make export-ipa`.
- [x] Upload recipe: `just upload` / `make upload`.

Notes:
- `export-ipa` requires `EXPORT_OPTIONS_PLIST` (defaults to `build/ExportOptions.plist`).
- `upload` requires `ASC_KEY_ID` and `ASC_ISSUER_ID`.
