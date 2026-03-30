# todo.md

todo.md is a filesystem-first task manager built around plain Markdown files. Each task is a real `.md` file with YAML frontmatter, and the app adds native Apple task views and workflows on top instead of hiding your data in a proprietary database.

## Why it exists

Most task apps force a tradeoff: polished UX with locked-in data, or portable text files with a rough daily workflow. todo.md is trying to close that gap. The files stay readable and writable outside the app, while the app handles capture, scheduling, reminders, review, widgets, and other native integrations.

That also makes the system easy to automate. A person, Shortcut, script, Obsidian vault, or AI agent can create and update tasks by writing Markdown the app already understands.

## Task format

Each task lives in a user-chosen folder as one Markdown file:

```md
---
title: Buy groceries
status: todo
scheduled: 2026-03-23
priority: medium
tags:
  - errands
source: user
---
Pick up fruit, rice, and coffee.
```

## Current capabilities

- native app targets for iPhone, iPad, and Mac, all using the same Markdown task format
- built-in views including Inbox, Today, Upcoming, Anytime, Someday, Flagged, My Tasks, Delegated, Logbook, Review, and an optional Pomodoro view
- quick entry with natural-language date parsing, plus full task detail editing
- custom perspectives with saved rules, widget support, and natural-language filter parsing
- recurring tasks, refs, assignees, blockers, checklists, location reminders, persistent reminders, and manual ordering
- local notifications, filesystem watching, Quick Find, share extension support, URL routing, widgets, and App Intents
- Apple Calendar overlays, Apple Reminders import, and voice capture for turning speech into tasks

## Current limits

- task bodies are still treated as plain text rather than fully rendered Markdown
- checklist items are supported, but true parent/child subtasks are not
- broader import/export coverage beyond Apple Reminders is still unfinished

todo.md is strongest today as a personal, Apple-first task manager with open files underneath it, not as a collaborative SaaS task platform or hosted sync service.
