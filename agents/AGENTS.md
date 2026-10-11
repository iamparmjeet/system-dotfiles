<!-- codebase-memory-mcp:start -->
# Codebase Memory

## Codebase Knowledge Graph (codebase-memory-mcp)

This project uses codebase-memory-mcp to maintain a knowledge graph of the codebase.
ALWAYS prefer MCP graph tools over grep/glob/file-search for code discovery.

### Priority Order
1. `search_graph` — find functions, classes, routes, variables by pattern
2. `trace_path` — trace who calls a function or what it calls
3. `get_code_snippet` — read specific function/class source code
4. `check_index_coverage` — validate candidate paths and missed ranges before claims
5. `query_graph` — run Cypher queries for complex patterns
6. `get_architecture` — high-level project summary

### Evidence tiers
- **Scout (Tier 1):** quick positive lookup with few calls and targeted source checks. Mark it provisional; do not make negative or exhaustive claims.
- **Verify (Tier 2, default):** task-directed graph evidence, relevant trace directions, exact snippets for material claims, and relevant pagination.
- **Auditor (Tier 3):** bounded-scope full verification with current generation, complete relevant pagination, both call directions and broader relationships when material, and every limitation disclosed.
- After candidate paths are known in any tier, call `check_index_coverage` once with every evidence path. Add relevant scopes for negative or exhaustive claims. A clean result means no recorded gap, not proof of completeness. For partial, skipped, excluded, stale, pending, or unknown coverage, read/grep the reported ranges or scope before relying on graph results.

### When to fall back to grep/glob
- Searching for string literals, error messages, config values
- Searching non-code files (Dockerfiles, shell scripts, configs)
- When MCP tools return insufficient results

### Examples
- Find a handler: `search_graph(name_pattern=".*OrderHandler.*")`
- Who calls it: `trace_path(function_name="OrderHandler", direction="inbound")`
- Read source: `get_code_snippet(qualified_name="pkg/orders.OrderHandler")`

### Session resets and subagents
- At session start or after compaction, confirm the nearest graph project and generation with `list_projects` or `index_status`, then choose Scout, Verify, or Auditor.
- Before spawning a subagent, query the graph and coverage in the parent. Pass the tier, project, generation/freshness, bounded scope, queries and pagination state, qualified symbols, paths, call-chain findings, coverage evidence with ranges/reasons, source fallback already performed, and unresolved questions in the delegated task context.
- Do not assume subagents inherit MCP access or the parent conversation. If a child lacks MCP tools, it must not call or claim MCP access. It should use the supplied evidence and read/grep exact source, especially every reported missed-coverage range.
<!-- codebase-memory-mcp:end -->

## Visual output

- For diagrams, charts, and any vector visual, emit **inline SVG**: write an `.svg` file and reference it as `![alt](/abs/path.svg)`. Do not default to PNG — SVG stays crisp at any zoom. Rasterize (via `rsvg-convert`) only when SVG is unsupported or the user asks.
- T3 Code's browser preview panel also renders SVG/HTML live: serve the file (e.g. `python3 -m http.server`) and open it with the preview tools.

## Cross-chat memory (Basic Memory)

This file is the single global instruction file for Codex, OpenCode and Claude Code (`~/.agents/AGENTS.md`, symlinked into each tool).

- **Shared store:** folder `~/basic-memory` (Basic Memory project `main`, private git repo `iamparmjeet/basic-memory`, database `~/.config/basic-memory/memory.db`). Follow that folder's `AGENTS.md` for filing and frontmatter conventions. Keep it separate from LifeOS: never write memory notes into the LifeOS vault.
- **One shared memory server:** `basic-memory-shared.service` serves Basic Memory at `http://127.0.0.1:8765/mcp`. Claude, Codex and OpenCode connect over HTTP; never configure a separate stdio Basic Memory process per chat. Earlier duplicate processes used substantial RAM and correlated with T3 stalls; causality was not established. CLI/file access remains the fallback if the shared service is unavailable.
- **Profile (automatic):** at session start, `~/.agents/hooks/agent-memory.py recall` injects `[agent-memory] Profile` (`~/basic-memory/Profile/`: `me.md`, `machine.md`, the `projects/*.md` whose `root` contains the cwd, `recent.md`) plus recent checkpoints. Claude and Codex get it via hooks, OpenCode via `~/.config/opencode/plugins/agent-memory.js`. Treat it as background knowledge about the user and verify time-sensitive details.
- **Learning:** a daily systemd user timer (`agent-memory-learn.timer`, 23:30) runs `agent-memory.py learn`. It distills new chats into `Profile/` using OpenCode DeepSeek Flash (free Muse as fallback), then commits and pushes. When the user says "remember that …", edit the relevant `Profile/` file directly: keep it short, replace contradicted facts, and commit.
- **Search:** prefer shared MCP `search_notes`, `read_note`, `recent_activity` and `build_context`. Use `rg -i "<term>" ~/basic-memory` or the one-shot CLI if MCP is unavailable. The shared service indexes file changes automatically.
- **Resume:** when the user says "continue", "where were we" or "back to …", or the request clearly relates to a listed checkpoint, use the `memory-continue` skill before answering. If no `[agent-memory]` context was injected, run `python3 -I ~/.agents/hooks/agent-memory.py recall --cwd "$PWD"` first.
- **Save:** when a decision, handoff or milestone lands, or the user says "save", "checkpoint" or "remember this chat", use `memory-capture` with `lifeos-memory-checkpoint` (MCP preferred, CLI fallback). Rewrite the same note in place; don't append logs or create duplicates. The skill commits and pushes.
- **Automatic context:** hooks write bounded context snapshots to `Sessions/_auto/<workspace>/<harness>-<full-id>.md` (git-ignored, pruned after 21 days without updates). Snapshots retain selected decisions/outcomes from earlier assistant replies, requests and the last reported status, with common credentials redacted. They are unverified source excerpts, not curated checkpoints or a complete transcript. `agent-memory-sweep.timer` scans available native Claude/Codex histories and paginated OpenCode API history every 15 minutes, catching missed hooks; daily learning promotes durable facts. New chats receive short recent-context excerpts automatically. Never edit generated snapshots by hand.
