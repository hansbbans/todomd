# todo.md v1 Test Matrix

Last updated: 2026-02-26

## Unit

- [x] Frontmatter parse/serialize round-trip with unknown key preservation.
- [x] Validation for enums/types/length constraints.
- [x] Filename slug/collision generation.
- [x] View membership predicate correctness.
- [x] RRULE recurrence edge cases (daily/weekly/monthly/yearly incl. leap).
- [x] NLP date parsing (`tomorrow`, `next friday`, `in 3 days`, absolute date).

## Integration

- [x] External add reflected by watcher and query.
- [x] External modify/defer flow and self-write suppression coverage.
- [x] External delete reflected by watcher summary/events.
- [x] In-app edit preserves unknown frontmatter fields.
- [x] Repeat completion creates next task instance.
- [x] Manual order persists across service instances (`.order.json`).
- [x] Conflict handling path exists for keep-local/keep-remote.

## UI/UX

- [x] Quick entry create flow.
- [x] Swipe complete/defer interactions.
- [x] View switching and task detail edit persistence.
- [x] Conflict detail compare view (side-by-side local/remote).
- [x] Source badge visibility for non-user tasks.

## Security/Resilience

- [x] Malformed YAML does not crash; diagnostics recorded.
- [x] Deeply nested frontmatter rejection.
- [x] Oversized body rejection.
- [x] Burst creation detection and alert path.

## Performance

- [x] Cold sync performance test (500 files) in automated tests.
- [x] Incremental sync performance test (10 changed files) in automated tests.
- [x] Query performance benchmark path in CLI benchmark tool.
- [x] Full benchmark report artifact at `docs/benchmarks/latest.json`.
