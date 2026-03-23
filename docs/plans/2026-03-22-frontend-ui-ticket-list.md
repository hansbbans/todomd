# Frontend UI Ticket List

Date: 2026-03-22
Status: Proposed

## North Star

- Desired visual language: Things 3
- Desired performance and responsiveness: Things 3
- Product qualities to optimize for: calm, warm, dense-but-readable, minimal chrome, fast capture, instant navigation, smooth motion, no visible jank

## Prioritization Rules

- Fix reliability problems before visual polish.
- Build one shared visual system before redesigning individual screens.
- Improve the main task flows before secondary tools and maintenance screens.
- Hold all UI changes to a Things 3 bar for both look and perceived speed.

## Ticket Summary

| ID | Priority | Ticket | Effort | Depends On |
|---|---|---|---|---|
| UI-001 | P0 | Stabilize onboarding to first-task capture flow | M | - |
| UI-002 | P0 | Shorten onboarding and strengthen completion handoff | M | UI-001 |
| UI-003 | P1 | Establish shared Things-style surface system | M | - |
| UI-004 | P1 | Unify core floating panels and cards under the shared system | M | UI-003 |
| UI-005 | P1 | Normalize main-screen hero, spacing, and empty-state rhythm | S | UI-003 |
| UI-006 | P1 | Make quick capture progressive and instant | M | UI-003 |
| UI-007 | P2 | Rework Quick Find for better pre-query value and grouped results | M | UI-003 |
| UI-008 | P2 | Simplify task detail hierarchy and reduce settings-like density | L | UI-003 |
| UI-009 | P2 | Reduce task-row accessory clutter and sharpen expanded-state affordances | M | UI-003 |
| UI-010 | P3 | Main-list performance parity pass | M | UI-003 |
| UI-011 | P3 | Search and capture latency budget pass on large datasets | M | UI-010 |
| UI-012 | P4 | Reorganize settings around real jobs | M | UI-003 |
| UI-013 | P4 | Bring secondary surfaces up to the same product standard | L | UI-003 |
| UI-014 | P5 | Accessibility, Dynamic Type, and lower-motion resilience pass | M | UI-004, UI-008 |

## Detailed Tickets

### UI-001: Stabilize onboarding to first-task capture flow

Problem:
- The first-run path is not reliable enough.
- Current evidence: the UI test `testOnboardingDefaultFolderThenQuickAddCreatesTaskAndAppStaysResponsive` fails because `inlineTask.titleField` stops being available after opening quick add.

Scope:
- Fix the onboarding-to-home-to-inline-add path.
- Make the inline composer keep stable focus and stable accessibility identity after it opens.
- Confirm the user can add a task, then immediately add another.

Acceptance criteria:
- A first-run user can complete onboarding, skip primers, tap add, type a title, save, and reopen add without UI breakage.
- The failing UI test passes consistently.
- No regressions in the existing expanded-task modal dismissal flow.

Suggested verification:
- Run the onboarding quick-add UI test.
- Run the expanded task date modal dismissal UI test.

### UI-002: Shorten onboarding and strengthen completion handoff

Problem:
- Onboarding explains the app well, but it is text-heavy and ends with a storage decision rather than a strong product moment.

Scope:
- Reduce copy and make each page do one job.
- Replace generic explanation with one stronger visual and one clearer action per page.
- Improve the final transition from onboarding into the main app so it feels intentional and fast.

Acceptance criteria:
- Onboarding can be scanned in seconds.
- The final step clearly communicates “you are ready to add tasks now”.
- The first-run experience feels closer to Things 3: confident, spare, and fast.

### UI-003: Establish shared Things-style surface system

Problem:
- Core surfaces use different shadows, gradients, corner treatments, and spacing, which weakens visual cohesion.

Scope:
- Define a single shared surface language for elevated cards, popup panels, inset utility surfaces, borders, and shadows.
- Define shared spacing, radius, border, and motion tokens for these surfaces.
- Keep the result restrained and quiet rather than decorative.

Acceptance criteria:
- Floating and elevated surfaces feel like members of the same family.
- Visual emphasis comes from layout and hierarchy first, not ornamental styling.
- The app reads as one product rather than a collection of individually styled screens.

### UI-004: Unify core floating panels and cards under the shared system

Problem:
- Quick add, Quick Find, reminders import, voice capture, and calendar cards each have a different visual treatment.

Scope:
- Apply the shared system to:
- Quick add
- Quick Find
- Inbox reminders import panel
- Voice ramble
- Today calendar card
- Expanded task card where appropriate

Acceptance criteria:
- These panels share the same visual grammar.
- No single panel feels more glossy or more decorative than the rest.
- The user can move between these surfaces without a style break.

### UI-005: Normalize main-screen hero, spacing, and empty-state rhythm

Problem:
- The best main screens have a strong Things-like rhythm, but the pattern is not fully consistent across list states and alternate views.

Scope:
- Standardize hero spacing, section spacing, empty-state placement, and screen rhythm across Inbox, Today, Upcoming, Review, Logbook, and custom lists.
- Make sure the first scroll screen always feels intentional, sparse, and easy to parse.

Acceptance criteria:
- Main screens share one consistent visual cadence.
- Empty states feel deliberate and restrained.
- Transitioning between main views feels like switching modes of one workspace.

### UI-006: Make quick capture progressive and instant

Problem:
- Quick capture exposes too many controls too early and does not yet feel as immediate as Things 3.

Scope:
- Keep the first step focused on entering a task.
- Reveal due date, tags, destination, reminders, and other fields only when they help.
- Reduce visible control density in the initial state.
- Tune keyboard and focus behavior for speed.

Acceptance criteria:
- A user can open capture and add a basic task with minimal visual noise.
- Optional fields remain easy to reach but are not competing for attention up front.
- Capture feels instant, stable, and lightweight.

### UI-007: Rework Quick Find for better pre-query value and grouped results

Problem:
- Quick Find opens as a small history-oriented card rather than a genuinely useful command surface.

Scope:
- Improve the zero-query state with smarter suggestions.
- Group results in a way that helps scanning.
- Refine vertical sizing and hierarchy so the card feels deliberate rather than cramped.
- Keep the result aligned with Things 3: fast, focused, quiet.

Acceptance criteria:
- Quick Find is useful before the user types.
- Results are easier to scan and understand.
- The search experience feels like a premium command palette, not a generic modal.

### UI-008: Simplify task detail hierarchy and reduce settings-like density

Problem:
- Task detail still reads like a long set of labeled controls more than a calm editor.

Scope:
- Rework the screen so title, notes, date, and the most-used metadata feel primary.
- Push less-used fields further back.
- Reduce divider-heavy row repetition.
- Preserve editing power while making the screen feel lighter and more focused.

Acceptance criteria:
- The screen feels closer to editing a task than configuring a form.
- The most common fields are obvious at a glance.
- The screen looks and behaves like a Things 3 task detail surface: quiet, direct, and efficient.

### UI-009: Reduce task-row accessory clutter and sharpen expanded-state affordances

Problem:
- Collapsed and expanded task rows carry useful actions, but the affordances are starting to compete visually.

Scope:
- Reevaluate checkbox, star, flag, inline actions, expanded footer actions, and metadata density.
- Keep what helps fast triage and remove or demote what creates clutter.
- Make expanded rows feel special and intentional, not just larger.

Acceptance criteria:
- Rows scan quickly.
- Expanded state has a clear purpose and hierarchy.
- The list keeps a Things-like calmness even when interactive controls are visible.

### UI-010: Main-list performance parity pass

Problem:
- The app’s desired responsiveness is Things 3, but the main list still needs a deliberate performance pass.

Scope:
- Measure and improve scroll smoothness, expand/collapse responsiveness, completion animation smoothness, and navigation transitions.
- Remove avoidable work from hot paths in the main task list.
- Confirm the UI remains responsive with realistic task counts.

Acceptance criteria:
- Scrolling and tapping feel immediate.
- Expand, complete, and navigate interactions do not visibly hitch.
- The main list feels fast enough to support a Things 3 comparison without apology.

### UI-011: Search and capture latency budget pass on large datasets

Problem:
- Search and capture must remain instant even as data volume grows.

Scope:
- Define acceptable latency targets for Quick Find, inline add, and quick entry.
- Test against larger representative datasets.
- Remove slow operations from the critical interaction path.

Acceptance criteria:
- Search opens quickly and updates quickly on realistic data.
- Capture surfaces appear and focus promptly.
- The app preserves a “fast enough to trust” feeling under load.

### UI-012: Reorganize settings around real jobs

Problem:
- Settings are organized by internal categories rather than the tasks a user is actually trying to do.

Scope:
- Reframe settings around jobs such as setup, capture, notifications, appearance, storage, and troubleshooting.
- Make the most important decisions easier to find.
- Demote purely technical or rarely used controls.

Acceptance criteria:
- Important settings can be found quickly without browsing multiple categories.
- The information architecture feels product-led rather than implementation-led.
- The settings experience feels closer to Things 3: spare, confident, and intentionally scoped.

### UI-013: Bring secondary surfaces up to the same product standard

Problem:
- Pomodoro, Perspectives, icon picker, conflict resolution, and unparseable-file flows still feel more utilitarian than the main app.

Scope:
- Apply the shared visual system and hierarchy rules to:
- Pomodoro
- Perspectives list and editor
- Icon picker
- Conflict resolution
- Unparseable files

Acceptance criteria:
- Secondary screens feel like part of the same app.
- Utility screens still look calm and considered.
- No major screen feels like a developer tool accidentally exposed to end users.

### UI-014: Accessibility, Dynamic Type, and lower-motion resilience pass

Problem:
- Several screens still rely on fixed sizing and custom motion that may not hold up well outside the default setup.

Scope:
- Audit larger text sizes across the main flows.
- Audit Reduce Motion behavior.
- Audit differentiation without color where color currently carries meaning.
- Improve VoiceOver labeling where controls are icon-heavy or state-heavy.

Acceptance criteria:
- Core flows remain usable and visually coherent at larger text sizes.
- Motion-heavy interactions degrade gracefully.
- Key state changes remain legible without relying on color alone.

## Recommended Execution Order

1. UI-001
2. UI-002
3. UI-003
4. UI-004
5. UI-005
6. UI-006
7. UI-008
8. UI-007
9. UI-009
10. UI-010
11. UI-011
12. UI-012
13. UI-013
14. UI-014

## Notes From Current Verification

- Verified pass: expanded task date modal dismisses correctly when tapping outside.
- Verified failure: onboarding to first inline quick-add is currently unstable in UI testing.
- Immediate implication: UI-001 should be treated as a blocking quality ticket before broader polish work.
