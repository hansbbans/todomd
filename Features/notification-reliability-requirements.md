# Notification Reliability Requirements

> **Priority:** Critical
> **Status:** Open problem
> **Scope:** Reminder delivery reliability for due tasks

## Problem Statement

Notification delivery is currently not reliable enough for due-task reminders. Users can miss reminders even when tasks have valid `due` + `due_time` values and notifications are enabled. This is a major product risk because reminders are a core behavior of todo.md.

## Why This Is Major

- Missed reminders directly break user trust.
- A missed reminder can cause real-world task failures (payments, deadlines, commitments).
- Current local-only scheduling depends on iOS execution timing and app refresh opportunities.

## Current Risk Areas

- App may not reschedule frequently enough when not foregrounded.
- Edge timing around exact due minute/second can skip delivery.
- iOS background execution is best-effort, not guaranteed.
- Local notification path has no server-side retry or delivery acknowledgement.

## Reliability Goal

Design and ship a “near-never-miss” notification system with observable delivery guarantees and fallback behavior.

## High-Level Requirements

1. Keep local scheduling robust for immediate/on-device behavior.
2. Add delivery observability (`planned`, `scheduled`, `delivered`, `acknowledged`, `missed`).
3. Introduce an authoritative delivery path that can retry on failures.
4. Support escalation/fallback for high-importance reminders.
5. Explicitly handle timezone change, clock change, permission change, and sync lag scenarios.

## Exit Criteria

- Miss rate is measurable and stays under an agreed threshold.
- Reproducible edge cases no longer miss reminders in QA scenarios.
- There is a documented incident/debug path for any missed reminder report.
