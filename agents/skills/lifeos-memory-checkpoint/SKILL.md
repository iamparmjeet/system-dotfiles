---
name: lifeos-memory-checkpoint
description: Apply the LifeOS filing and privacy conventions when capturing or updating a conversation in Basic Memory. Use with memory-capture when the user asks to checkpoint, save, process, or remember a chat.
---

# LifeOS Memory Checkpoint

Follow the installed `memory-capture` skill for synthesis and `memory-notes` for Basic Memory syntax. This skill only adds the user's storage policy.

## Destination

Write to Basic Memory project `main` (folder `~/basic-memory`, a private git repo) under:

```text
Sessions/<YYYY>/<workspace>/
```

Write only through the Basic Memory tools. Never write memory notes into the LifeOS vault; `~/Re-Learning/lifeos/00-09_System/07-Basic-Memory` is a frozen pre-2026-10-07 archive.

## Transport (shared MCP with CLI fallback)

Prefer the shared MCP tools (`search_notes`, `write_note`, `edit_note`, `move_note`, `read_note`). If the connection is unavailable, use the CLI with identical semantics; never launch another long-running server:

```bash
export BASIC_MEMORY_CONFIG_DIR=/home/parm/.config/basic-memory
basic-memory tool search-notes "<topic>" --project main
basic-memory tool write-note --project main --folder "Sessions/<YYYY>/<workspace>" --title "<title>" < /tmp/checkpoint.md
```

Keep filenames, frontmatter, and the git backup step identical either way.

Derive `<workspace>` from the current project or working-directory basename. Use `Parm` for `/home/parm`; otherwise preserve the source folder's spelling, such as `parm-skills`.

Use this filename:

```text
<YYYYMMDDHHmm>-<topic-slug>.md
```

Get the local timestamp from the system. Use the harness chat title as the topic when it is available and accurately describes the outcome; otherwise derive a short action-oriented topic from the conversation. Convert it to lowercase kebab-case and omit generic words such as `chat`, `session`, and `conversation`. The user may provide the topic explicitly. The compact date-first filename is the canonical chronological key; keep the note title human-readable.

## Frontmatter

Create notes with `note_type="session"`, relevant tags, and this metadata:

```yaml
created: <ISO-8601 timestamp>
modified: <ISO-8601 timestamp>
workspace: <workspace>
working_directory: <absolute working directory>
harness: <codex|opencode|claude|other>
thread_id: <stable thread id, when available>
status: <active|complete>
```

Let Basic Memory generate `title`, `type`, `tags`, and `permalink`. Do not put YAML in the `content` argument.

## Capture

1. Force the zero-cost breadcrumb first (no MCP server): run `python3 -I ~/.agents/hooks/agent-memory.py autosave --harness <codex|claude|opencode>` via shell so the current turn is preserved even if the session ends abruptly. Provider-native memory (Codex memories, Claude auto memory) runs on its own — do not duplicate its per-repo details here.
2. Search `main` by `thread_id`; without one, search by topic, workspace, and date.
2. Synthesize the current state according to `memory-capture`. Save decisions, durable context, outcomes, open loops, and next steps rather than a transcript.
3. For a new note, call `write_note` in `Sessions/<YYYY>/<workspace>`, then call `move_note` with the exact canonical filename.
4. For the same thread, keep its path and title. Rewrite the note coherently with `edit_note`; replace the root heading's contents and merge updated metadata instead of appending a log.
5. Read the final note and confirm its path matches the convention.
6. Back it up: `git -C ~/basic-memory add -A && git -C ~/basic-memory commit -m "checkpoint: <workspace>/<topic-slug>" && git -C ~/basic-memory push`. Raw `Sessions/_auto/` breadcrumbs are git-ignored. If the push fails, report it; the local commit still counts.

The checkpoint is complete only after the note is verified and committed.

## Restore

On a new machine: `git clone https://github.com/iamparmjeet/basic-memory.git ~/basic-memory`, run `basic-memory project add main ~/basic-memory` (or `project move` if `main` exists), then `basic-memory reindex -p main --full`.

## Boundary

This project is available to every configured harness. Capture only information appropriate for that shared tier. Keep raw transcripts, secrets, sensitive personal details, and private full-LifeOS content out unless the user explicitly asks to publish them here.

Open loops describe session state; they do not become a parallel task system. Canonical tasks remain in LifeOS.
