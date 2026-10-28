# Reply density test vectors

`v1.json` is the canonical, versioned behavior contract shared by the
PiliPlus Purify app and its companion browser extension.

## Versioning

- `schemaVersion` changes only when the JSON shape or field meaning changes.
- Existing cases must not be silently reinterpreted.
- Consumers outside this repository must pin an exact Git commit or release
  reference instead of reading the moving `purify` branch.
- The browser extension should check out or download this exact file in CI; it
  must not maintain a hand-copied equivalent.

## Contract

Each case contains:

- `input`: raw message, verified `atNameToMid` mapping, structured media
  markers, nickname/behavior evidence, and explicit detector configuration.
- `expected`: one mutually exclusive density candidate, both mention metrics,
  effective text length, recoverable fold/review decisions, AI evidence, and
  stable reason labels.
- `coverage`: quality-gate tags verified by the Dart test suite.

Automatic assessments in this contract never create permanent blacklist
entries. A consumer may present a recoverable fold or pending-review item, but
permanent account and keyword actions always require user confirmation.
