# Natural Language Perspectives — Requirements for Codex

> **Feature:** Custom Perspectives via Natural Language Input (v2)
> **Replaces:** Visual rule builder approach (deprecated from previous user stories doc)
> **Core idea:** Users describe what they want to see in plain English. The app parses their intent into structured filter rules and creates the perspective. No dropdowns, no query syntax, no rule hierarchy to learn.

---

## Design Philosophy

OmniFocus makes you build perspectives with nested Boolean rule trees. Todoist makes you memorize a filter query syntax. Both approaches require the user to think like a database engineer.

todo.md takes a different approach: **describe what you want, and we'll build the filter for you.**

The underlying filter engine (`.perspectives.json`, SwiftData predicates, AND/OR/NOT rule trees) remains the same as previously specified. What changes is the **input method** — natural language replaces the visual builder as the primary creation flow. The structured rule editor still exists as an "Advanced" escape hatch for power users who want to hand-tune rules, but 90%+ of perspective creation should happen via natural language.

---

## Architecture Overview

```
┌─────────────────────┐
│  User types/speaks   │
│  natural language    │
│  query               │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  NL Parser           │
│  (on-device first,   │
│   LLM fallback)      │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Structured rules    │
│  (PerspectiveRules   │
│   JSON object)       │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  Preview: show       │
│  matching tasks +    │
│  human-readable      │
│  rule summary        │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  User confirms →     │
│  Save to             │
│  .perspectives.json  │
└─────────────────────┘
```

---

## Parsing Strategy: Two-Tier System

### Tier 1: On-Device Deterministic Parser (fast, private, no network)

A rule-based parser that handles the most common query patterns. This should cover 80%+ of real-world queries with zero latency and no API cost.

**How it works:**
1. Tokenize the input string.
2. Match against a grammar of known patterns (see pattern table below).
3. Extract field references, operators, and values.
4. Assemble into a `PerspectiveRules` JSON object.
5. If the parser achieves high confidence (all tokens consumed, no ambiguity), return the result directly.
6. If the parser fails or has low confidence (unrecognized tokens, ambiguous structure), fall through to Tier 2.

**Pattern grammar (non-exhaustive — Codex should expand):**

| Pattern | Example Input | Parsed Rule |
|---|---|---|
| `due today` | "all items due today" | `{ "field": "due", "op": "on", "value": "today" }` |
| `due this week` | "tasks due this week" | `{ "field": "due", "op": "in_next", "value": 7, "unit": "days" }` |
| `due before [date]` | "due before Friday" | `{ "field": "due", "op": "before", "value": "2026-02-27" }` |
| `overdue` | "overdue items" | `{ "field": "due", "op": "before", "value": "today" }` |
| `due today or overdue` | "all items due today or overdue" | `{ "operator": "OR", "conditions": [due=today, due<today] }` |
| `no due date` | "tasks with no due date" | `{ "field": "due", "op": "is_nil" }` |
| `scheduled [date]` | "scheduled for Monday" | `{ "field": "scheduled", "op": "on", "value": "2026-03-02" }` |
| `deferred` | "deferred tasks" | `{ "field": "defer", "op": "is_not_nil" }` |
| `in project [name]` | "items in project Margin" | `{ "field": "project", "op": "equals", "value": "Margin" }` |
| `in area [name]` | "work tasks" / "in area Work" | `{ "field": "area", "op": "equals", "value": "Work" }` |
| `in projects [A] and [B]` | "in projects B and C" | `{ "operator": "OR", "conditions": [project=B, project=C] }` |
| `tagged [tag]` | "tagged @errands" | `{ "field": "tags", "op": "contains", "value": "errands" }` |
| `untagged` | "untagged tasks" | `{ "field": "tags", "op": "is_empty" }` |
| `high priority` | "high priority items" | `{ "field": "priority", "op": "equals", "value": "high" }` |
| `flagged` | "flagged tasks" | `{ "field": "flagged", "op": "equals", "value": true }` |
| `quick tasks` / `under N min` | "tasks under 15 minutes" | `{ "field": "estimated_minutes", "op": "less_than", "value": 15 }` |
| `someday` | "someday tasks" | `{ "field": "status", "op": "equals", "value": "someday" }` |
| `inbox` | "inbox items" | `{ "operator": "AND", "conditions": [area=nil, project=nil] }` |
| `completed` | "completed tasks" | `{ "field": "status", "op": "equals", "value": "done" }` |
| `completed this week` | "tasks completed this week" | `{ "operator": "AND", "conditions": [status=done, completed=this_week] }` |
| `created by [source]` | "tasks from claude-agent" | `{ "field": "source", "op": "equals", "value": "claude-agent" }` |
| `repeating` | "recurring tasks" | `{ "field": "recurrence", "op": "is_not_nil" }` |

**Combinators the parser must handle:**

| Combinator | Example | Logic |
|---|---|---|
| `and` / `AND` / `,` / `+` | "due today and flagged" | AND |
| `or` / `OR` | "in project A or project B" | OR |
| `not` / `except` / `excluding` / `but not` | "all work tasks except completed" | NOT (exclusion) |
| Implicit AND | "high priority work tasks due this week" | AND (sequential qualifiers) |

**Implicit AND is the default.** "High priority work tasks due this week" means: priority=high AND area=Work AND due=this_week. This matches how humans naturally stack qualifiers.

**Entity resolution:**
- Project names and area names are matched against the current SwiftData index using case-insensitive fuzzy matching.
- If "Margin" matches a project called "Margin Call Q3", use the match and note it in the preview.
- If no match is found, show a warning: "No project named 'Margin' found. Did you mean: [suggestions]?"
- Tag names are matched similarly, with `@` prefix stripped if present.

### Tier 2: LLM-Powered Parser (complex queries, disambiguation)

For queries the deterministic parser can't handle confidently, fall back to an LLM call.

**When Tier 2 activates:**
- The deterministic parser returns low confidence (unrecognized tokens, ambiguous structure).
- The query uses complex natural language that doesn't match known patterns (e.g., "things I should work on when I'm low energy and have a short window").
- The query references concepts that require inference (e.g., "urgent" → high priority + due soon).

**LLM prompt structure:**
```
You are a task filter parser for a markdown-based task manager.

The user wants to create a saved filter (called a "perspective"). 
Parse their natural language query into a structured JSON filter.

Available fields and their types:
- title: string
- status: enum [todo, in-progress, done, cancelled, someday]
- description: string
- source: string
- due: date (or null)
- scheduled: date (or null)  
- defer: date (or null)
- created: datetime
- modified: datetime
- completed: datetime (or null)
- area: string (or null)
- project: string (or null)
- tags: string[] 
- priority: enum [none, low, medium, high]
- flagged: boolean
- recurrence: string (or null)
- estimated_minutes: integer (or null)

Known areas: {list from index}
Known projects: {list from index}
Known tags: {list from index}

Operators: equals, not_equals, in, contains, before, after, on, 
between, in_next, in_past, less_than, greater_than, is_nil, 
is_not_nil, is_empty, string_contains

Logical operators: AND, OR, NOT (nestable)

User query: "{user input}"
Today's date: {today}

Return ONLY a JSON object with this structure:
{
  "name": "suggested perspective name",
  "rules": { ... nested rules ... },
  "sort": { "field": "...", "direction": "asc|desc" },
  "group_by": "..." or null,
  "confidence": 0.0-1.0
}
```

**LLM selection:**
- Use Claude API (already specced for voice ramble mode — shared infrastructure).
- On-device model (Apple Intelligence / Core ML) as future option when capable enough.
- User setting: "Allow cloud AI for perspective parsing" (default: on). If off, only Tier 1 is used.

**Latency target:** Tier 2 should return within 2 seconds. Show a subtle loading indicator ("Thinking...") while waiting.

---

## User Experience Flow

### Flow 1: Create Perspective from Natural Language

1. User taps "+" in sidebar → "New Perspective"
2. **A text field appears with placeholder: "Describe what you want to see..."**
   - Keyboard opens. Microphone button available for dictation.
3. User types: `all items due today or overdue`
4. As the user types (debounced 500ms after last keystroke), the parser runs:
   - Task list behind the input field filters live to show matching tasks.
   - Below the input: human-readable summary of parsed rules appears.
   - Example: "Showing tasks where **due date is today** OR **due date is before today**. **14 tasks match.**"
5. User reviews the preview. Two options:
   - **"Save Perspective"** → Name picker appears (pre-filled with suggested name, e.g., "Due Today or Overdue"), icon/color picker, then save.
   - **"Refine"** → User modifies the query text or taps "Advanced" to see/edit the structured rules.
6. Saved. Perspective appears in sidebar.

### Flow 2: Quick Filter (Ephemeral, Not Saved)

1. From any view, user swipes down (or taps search icon) to reveal a filter bar.
2. User types a natural language query: `high priority work tasks`
3. The current view filters live to show only matching tasks.
4. A "Save as Perspective" button appears if the user wants to persist the filter.
5. Dismissing the filter bar restores the previous view.

### Flow 3: Modify Existing Perspective via Natural Language

1. User long-presses a perspective → "Edit"
2. The perspective editor opens with the **current query displayed as natural language** (reverse-generated from the structured rules).
3. User can modify the text and re-parse, or tap "Advanced" to edit rules directly.

### Flow 4: Voice Input

1. User taps microphone button in the perspective input field.
2. Speech-to-text (on-device via `SFSpeechRecognizer`) transcribes in real-time.
3. On stop, the transcript is parsed through the same Tier 1 → Tier 2 pipeline.
4. Same preview/confirm flow as text input.

---

## Reverse Generation: Rules → Natural Language

For editing existing perspectives and for the human-readable preview, we need to convert structured rules back into natural language.

**Requirements:**
- Every `PerspectiveRules` JSON object must be expressible as a human-readable English sentence.
- The generated text should read naturally, not like a query language dump.

**Examples:**

| Rules JSON | Generated Natural Language |
|---|---|
| `{field: "due", op: "on", value: "today"}` | "due today" |
| `{operator: "OR", conditions: [{due on today}, {due before today}]}` | "due today or overdue" |
| `{operator: "AND", conditions: [{area: "Work"}, {status in [todo, in-progress]}, {priority: "high"}]}` | "high priority active Work tasks" |
| `{operator: "AND", conditions: [{project: "Margin"}, {due in_next 7 days}]}` | "items in project Margin due this week" |
| `{operator: "AND", conditions: [{flagged: true}, {estimated_minutes < 15}]}` | "flagged quick tasks under 15 minutes" |

**Implementation:** A `RulesNaturalizer` class that walks the rule tree and generates English fragments, joined with "and" / "or" / "excluding". Doesn't need to be perfect prose — clarity over elegance.

---

## Suggested Names Auto-Generation

When the user saves a perspective, suggest a concise name derived from the query.

**Rules for name generation:**
1. Use the natural language query as the starting point.
2. Strip filler words ("all", "items", "tasks", "things", "show me").
3. Capitalize appropriately.
4. Max 40 characters — truncate with "..." if needed.

**Examples:**

| Query | Suggested Name |
|---|---|
| "all items due today or overdue" | "Due Today or Overdue" |
| "high priority work tasks" | "High Priority Work" |
| "items in project Margin due this week" | "Margin — Due This Week" |
| "flagged tasks under 15 minutes" | "Flagged Quick Tasks" |
| "completed this week" | "Completed This Week" |
| "someday tasks in area Personal" | "Personal Someday" |

User can always override the suggested name.

---

## Error Handling & Disambiguation

### Ambiguous queries

If the parser can't determine intent with high confidence, show disambiguation options.

**Example:** User types "margin"
- Could mean: project named "Margin", or tasks containing "margin" in the title.
- Show: "Did you mean: **Tasks in project 'Margin'** or **Tasks with 'margin' in the title**?" (tappable options)

### No matches

If the parsed rules return zero tasks:
- Show: "No tasks match: **[human-readable rules]**"
- Below: "This perspective will show tasks when they match these criteria. Save anyway?" 
- This is valid — a "Due Tomorrow" perspective might be empty today but useful tomorrow.

### Unrecognized entity names

If the query references a project/area/tag that doesn't exist:
- Show: "No project named 'Margarine' found."
- If fuzzy match finds a close candidate: "Did you mean **'Margin'**?" (tappable)
- If no close match: "Save anyway? This perspective will show tasks if a project named 'Margarine' is created later."

### Conflicting rules

If the query produces logically contradictory rules (e.g., "completed tasks that are due today"):
- Parse it as-is. Don't second-guess the user — some people track recently-completed tasks with due dates.
- Show the match count. If zero, the user will notice and adjust.

---

## Advanced Editor (Escape Hatch)

The visual rule builder from the previous user stories doc is retained as an "Advanced" mode, accessible via a toggle at the bottom of the perspective editor.

**When to surface it:**
- "Advanced" link at the bottom of the NL input screen.
- Automatically shown if the user's query generates rules the NL parser can't round-trip cleanly.
- Power users who prefer direct rule manipulation.

**The advanced editor shows:**
- The full rule tree (same as previously specced: nested AND/OR/NOT groups, field/operator/value pickers).
- Any rule can be edited directly.
- Changes in the advanced editor update the natural language preview above.

**Principle:** Natural language is the front door. The advanced editor is the service entrance. Both produce and consume the same `PerspectiveRules` JSON.

---

## Data Model (No Change)

The `.perspectives.json` schema from the previous user stories doc is unchanged. Natural language input is a UI concern — the storage format is the same structured rules JSON. The only addition:

```json
{
  "perspective-id-1": {
    ...existing fields...,
    "source_query": "all items due today or overdue"
  }
}
```

`source_query` stores the original natural language input for round-tripping in the editor. Optional — perspectives created via the advanced editor won't have this field.

---

## Performance Requirements

| Metric | Target |
|---|---|
| Tier 1 parse latency | < 50ms (on-device, deterministic) |
| Tier 2 parse latency | < 2 seconds (LLM API call) |
| Live filter update | < 100ms after parse completes (SwiftData query) |
| Debounce on keystroke | 500ms (don't re-parse on every character) |
| Fuzzy entity matching | < 20ms against index of up to 500 projects/areas/tags |

---

## Testing Requirements

### Unit Tests for Tier 1 Parser

**Each test: input string → expected `PerspectiveRules` JSON**

```
// Simple field matches
"due today" → {field: "due", op: "on", value: "today"}
"overdue" → {field: "due", op: "before", value: "today"}
"high priority" → {field: "priority", op: "equals", value: "high"}
"flagged" → {field: "flagged", op: "equals", value: true}
"someday" → {field: "status", op: "equals", value: "someday"}
"in project Margin" → {field: "project", op: "equals", value: "Margin"}
"work tasks" → {field: "area", op: "equals", value: "Work"}
"tagged errands" → {field: "tags", op: "contains", value: "errands"}
"under 15 minutes" → {field: "estimated_minutes", op: "less_than", value: 15}
"repeating tasks" → {field: "recurrence", op: "is_not_nil"}
"no due date" → {field: "due", op: "is_nil"}
"completed" → {field: "status", op: "equals", value: "done"}

// Combinators
"due today or overdue" → OR[due=today, due<today]
"due today and flagged" → AND[due=today, flagged=true]
"in projects B and C" → OR[project=B, project=C]
"work tasks except completed" → AND[area=Work, NOT[status=done]]
"high priority work tasks due this week" → AND[priority=high, area=Work, due=this_week]

// Implicit AND (sequential qualifiers)
"flagged high priority" → AND[flagged=true, priority=high]
"work tasks due tomorrow" → AND[area=Work, due=tomorrow]

// Edge cases
"" → (empty rules — show all tasks)
"everything" → (empty rules — show all tasks)
"all tasks" → (empty rules — show all tasks)
"asdfghjkl" → (Tier 1 fails → fall through to Tier 2)
"tasks I should do when I'm tired" → (Tier 1 fails → Tier 2 infers: low energy tag or low priority)
```

### Integration Tests

- Parse → SwiftData query → verify correct tasks returned
- Parse → save to `.perspectives.json` → reload → verify rules intact
- Parse → reverse generate NL → verify human-readable output
- Tier 1 fail → Tier 2 call → verify fallback works
- Fuzzy entity match: "margn" → suggests "Margin"

### User Acceptance Tests

- Create 5 perspectives via NL, verify each shows correct tasks
- Edit a perspective by modifying its NL query, verify tasks update
- Create a perspective via NL, open in Advanced editor, verify rules match
- Create a perspective via Advanced editor, verify NL preview is sensible
- Voice input → perspective creation → verify end-to-end

---

## Implementation Phases

### Phase 1: Tier 1 Parser + Live Preview
- Build the deterministic parser with the pattern grammar above.
- Wire up live filtering: text input → parse → SwiftData query → update task list.
- Show human-readable rule summary below input.
- Save flow with name suggestion.
- No LLM, no voice — just typed NL with deterministic parsing.

### Phase 2: LLM Fallback (Tier 2)
- Integrate Claude API for Tier 2 parsing.
- Add confidence scoring to Tier 1 to know when to fall through.
- Add "Allow cloud AI" user setting.
- Handle disambiguation UI.

### Phase 3: Voice Input
- Wire up `SFSpeechRecognizer` to the same input field.
- Transcript → Tier 1/2 pipeline → preview → save.

### Phase 4: Refinements
- Reverse NL generation (rules → English) for editing existing perspectives.
- Auto-suggested names.
- Quick filter bar (ephemeral, non-saved filtering from any view).
- Advanced editor escape hatch.

---

## Open Questions

1. **Should the quick filter bar (Flow 2) be v2 or v1?** Ephemeral NL filtering from any view is simpler than saved perspectives and could ship in v1 as a precursor. The parser work carries over.

2. **Tier 2 cost management.** Each LLM call costs money. Should we cache common queries? Rate limit? Show a "this uses cloud AI" indicator?

3. **Multi-language support.** The Tier 1 parser is English-only initially. Tier 2 (LLM) handles any language natively. Is English-only acceptable for v2 launch?

4. **"Smart" inferences.** Should Tier 2 be allowed to infer things like "urgent" → high priority + due within 3 days? Or should we restrict to literal field mappings? Inference is more natural but less predictable.
