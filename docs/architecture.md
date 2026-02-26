# todo.md v1 Architecture

This document implements the approved v1 blueprint:
- Filesystem markdown files are canonical data.
- SwiftData (in app layer) acts as read index cache.
- Core domain and parser logic lives in `TodoMDCore`.
- iOS app target (`TodoMDApp`) composes view + integration features.

## Layers

- `Contracts`: schema, identifiers, DTOs, validation constraints.
- `Parsing`: frontmatter parser/serializer and date decoding.
- `Domain`: query engine, lifecycle logic, recurrence.
- `Storage`: repositories, file watcher, order sidecar handling.
- `Notifications`: deterministic notification planning and IDs.
- `Integration`: URL routing and external task contract.
- `Theme`: token model with v2-ready loading abstraction.
- `Observability`: sync snapshots, counters, and diagnostics models.

## Security Baseline (v1)

- Field and body length limits are enforced in validation.
- Enum and date parsing is strict with non-crashing errors.
- Unparseable documents are tracked via diagnostics.
- Burst create detection triggers a rate-limit event path.
- Body remains plain text in v1.
