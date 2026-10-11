# Restore agent chats, T3 Code and Basic Memory (backup of 2026-10-11)

Order: install Omarchy -> run `~/system-dotfiles/restore.sh` (steps 3-5 install the tools)
-> quit T3 Code and every agent CLI -> then unpack these on top.

```bash
B=/run/media/$USER/AMAR_WD/PARM/System-Reset-2026-10-11
x() { zstd -dc "$B/$1" | tar -C "$2" -xf -; }   # unpack archive into a folder

# Claude Code (chats = ~/.claude/projects)
x agents/claude.tar.zst ~ && cp "$B/agents/claude.json" ~/.claude.json
cp -r "$B/agents/claude-db/." ~/.claude/ 2>/dev/null

# Codex (chats = ~/.codex/sessions + sqlite files)
x agents/codex.tar.zst ~ && cp -r "$B/agents/codex-db/." ~/.codex/

# OpenCode (chats = ~/.local/share/opencode/opencode.db)
x agents/opencode-data.tar.zst ~/.local/share && cp -r "$B/agents/opencode-db/." ~/.local/share/opencode/
x agents/opencode-config.tar.zst ~/.config && (cd ~/.config/opencode && npm install)
x agents/opencode-state.tar.zst ~/.local/state
x agents/pi.tar.zst ~                                  # if you use pi
x agents/dot-agents.tar.zst ~                          # ~/.agents (also in system-dotfiles)

# T3 Code (threads = ~/.t3/userdata/statev2.sqlite)
x t3/t3-userdata.tar.zst ~/.t3 && cp -r "$B/t3/userdata-db/." ~/.t3/userdata/
x t3/t3-misc.tar.zst ~
x t3/desktop-t3code.tar.zst ~/.config; x t3/desktop-t3code-v2.tar.zst ~/.config
x t3/local-share-t3code.tar.zst ~/.local/share
cp "$B"/t3/t3 "$B"/t3/t3-db-nocow "$B"/t3/t3-stall-watch ~/.local/bin/ && chmod +x ~/.local/bin/t3*

# Basic Memory (notes are also on GitHub: iamparmjeet/basic-memory)
x basic-memory/basic-memory-notes.tar.zst ~           # includes git-ignored Sessions/_auto
x basic-memory/basic-memory-config.tar.zst ~/.config && cp -r "$B/basic-memory/config-db/." ~/.config/basic-memory/
systemctl --user restart basic-memory-shared
```

Notes
- Databases (`*-db/` folders) were taken with `sqlite3 .backup`, so they are consistent even though T3 was running.
- Not included (re-downloaded/rebuilt): CLI binaries (`.codex/packages`, `opencode-v2`, `.t3/tools`), caches,
  logs, git worktrees (all branches were pushed), old `.t3.bak` / `.t3.pre-fix` copies.
- Claude/Codex/OpenCode sign-in tokens are inside these archives; keep this drive private.
- If T3 shows old worktree paths for rently/Himrix threads, those folders no longer exist; the branches are on GitHub.
