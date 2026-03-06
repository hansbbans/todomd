# Things Parity Primary Task Lists

Date: 2026-03-06

## Goal

Implement the primary iPhone parity work from `docs/todomd-things-design-spec.md`, including the final compact navigation structure.

## Completed Work

1. Switch the primary app theme usage to semantic system colors so grouped backgrounds, labels, separators, overdue states, and accent color match iOS more closely.
2. Remove the floating action button from the main task experience and replace it with a toolbar `+` entry point.
3. Restyle primary task lists to `.plain`, clear row backgrounds, and remove section headers that only repeat the current view title.
4. Rebuild task rows around a Things-style checkbox, row spacing, metadata line, and flag treatment.
5. Update completion to the Things sequence: tap haptic, checkbox fill, short delay, lift/fade out, then filesystem completion.
6. Add inline task creation at the top of supported task lists with immediate focus plus a lightweight quick-add accessory strip for date, destination, tags, and flag state.
7. Replace the compact custom bottom bar with a native five-tab `TabView`: Inbox, Today, Upcoming, Areas, and Logbook.
8. Rework the compact browse/settings information architecture into an Areas tab that also exposes lists, projects, perspectives, tags, and settings.
9. Add a real Logbook built-in view for completed and cancelled tasks with recency-based ordering.

## Follow-up

1. Full Things-style swipe parity is still optional polish beyond the scope of the primary-list plan.

## Verification

1. Build the app target after the UI refactor.
2. Run the existing core test suite to catch any shared-model regressions.
