# TODOS

Items deferred from the ecosystem-first roadmap (2026-03-24 CEO review).

## P2: Obsidian Integration Guide

**What:** Document how to use Dataview or Templater to embed todo.md tasks in Obsidian daily notes.

**Why:** Killer demo for the interop story. "Open Obsidian, see your tasks" is the moment the filesystem-as-API thesis becomes tangible.

**Context:** Tasks live in iCloud Drive as `.md` files with YAML frontmatter. Obsidian can already see them if the vault includes or symlinks the todo.md folder. The frontmatter is Obsidian-compatible. A Dataview query like `TABLE title, status, due FROM "todo.md" WHERE status = "todo"` should work with minimal setup. The guide should cover: symlink setup, Dataview query examples, daily note template integration, and known limitations.

**Effort:** S (1-2 hours for a good guide)

**Depends on:** Nothing (files already work). Better after `.schema.json` ships so the guide can reference it.
