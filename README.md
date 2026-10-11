# system-dotfiles

My Omarchy setup: one script rebuilds a fresh install, asking before each step.

## Fresh install
```bash
gh auth login                       # needed for private repos (basic-memory, pipe)
git clone https://github.com/iamparmjeet/system-dotfiles ~/system-dotfiles
~/system-dotfiles/restore.sh
```
Steps (each one optional, safe to re-run; anything replaced goes to `~/.restore-backup-<date>/`):

1. **Packages** - `packages/*.txt` groups, untick what you don't need. Installed with `yay --needed`.
2. **Dotfiles** - stows `config/`, `local/`, `zshrc/` into `~`. Tmux stays Omarchy's.
3. **Agent CLIs** - Claude Code (native installer), Codex (standalone installer), OpenCode v2 (npm prefix
   `~/.local/share/opencode-v2`). These are the install types T3 Code can update itself.
   Never install them via the Omarchy AI menu, mise or pacman: those wrappers loop under T3.
4. **Agent config** - one `AGENTS.md` for all tools, memory hooks, and every skill linked into
   `~/.claude/skills`, `~/.codex/skills`, `~/.config/opencode/skills`.
5. **Basic Memory** - one shared MCP server (`basic-memory-shared.service`, `127.0.0.1:8765`) used by
   Claude, Codex and OpenCode, plus the sweep/learn timers.
6. **Code repos** - clones everything in `repos.txt`.
7. **Secrets** - copies `.env*` / `.dev.vars*` back from the SSD backup (they are never in git).

## Before resetting
`./backup-agents.sh /run/media/$USER/AMAR_WD/PARM/System-Reset-<date>` copies Claude/Codex/OpenCode chats, T3 threads and Basic Memory to the SSD (consistent SQLite snapshots). Unpack with `agents/RESTORE-chats.md`.

```bash
~/system-dotfiles/backup.sh   # refresh package snapshot, AGENTS.md, hooks, skills, units
git -C ~/system-dotfiles diff # review, then commit and push
```
`backup.sh` warns about newly installed packages that aren't in a group yet, and refuses to finish
if it spots anything that looks like a key or token. This repo is public.
