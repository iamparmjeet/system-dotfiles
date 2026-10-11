#!/usr/bin/env bash
# One-click restore for a fresh Omarchy install.
#   git clone https://github.com/iamparmjeet/system-dotfiles ~/system-dotfiles
#   ~/system-dotfiles/restore.sh
# Every step asks first and is safe to re-run.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
A="$REPO/agents"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$HOME/.restore-backup-$STAMP"
FAILED=()

say()  { gum style --foreground 212 --bold "==> $*"; }
info() { gum style --foreground 245 "    $*"; }
warn() { gum style --foreground 214 "    ! $*"; }
fail() { gum style --foreground 196 "    x $*"; FAILED+=("$*"); }

# Move an existing real file/dir out of the way before we replace it.
park() {
  local t="$1"
  [ -e "$t" ] && [ ! -L "$t" ] || return 0
  mkdir -p "$BACKUP_DIR/$(dirname "${t#"$HOME"/}")"
  mv "$t" "$BACKUP_DIR/${t#"$HOME"/}"
  info "moved existing ${t/#$HOME/~} to ${BACKUP_DIR/#$HOME/~}"
}

link() { mkdir -p "$(dirname "$2")"; [ -L "$2" ] && rm "$2"; park "$2"; ln -s "$1" "$2"; }

# --- 1. packages ---------------------------------------------------------------
step_packages() {
  say "Packages"
  local groups picked=()
  groups=$(cd "$REPO/packages" && ls *.txt | sed 's/\.txt$//')
  local chosen
  chosen=$(gum choose --no-limit --selected="$(echo "$groups" | paste -sd,)" \
    --header "Which package groups? (space toggles, enter confirms)" $groups) || return 0
  for g in $chosen; do
    local items
    items=$(sed 's/#.*//' "$REPO/packages/$g.txt" | awk 'NF{print $1}')
    local sel
    sel=$(gum choose --no-limit --selected="$(echo "$items" | paste -sd,)" \
      --header "$g: untick anything you don't want" $items) || continue
    picked+=($sel)
  done
  [ ${#picked[@]} -eq 0 ] && { info "nothing selected"; return; }
  info "installing ${#picked[@]} packages with yay (already-installed ones are skipped)"
  yay -S --needed --noconfirm "${picked[@]}" || fail "some packages failed to install, re-run this step to retry"
}

# --- 2. dotfiles -------------------------------------------------------------
step_dotfiles() {
  say "Dotfiles (stow)"
  command -v stow >/dev/null || yay -S --needed --noconfirm stow
  local pkgs chosen
  pkgs=$(cd "$REPO" && for d in config local zshrc; do [ -d "$d" ] && echo "$d"; done)
  chosen=$(gum choose --no-limit --selected="$(echo "$pkgs" | paste -sd,)" \
    --header "Which dotfile groups to link into ~ ?" $pkgs) || return 0
  for p in $chosen; do
    # park any real files that would block the symlinks
    (cd "$REPO/$p" && find . -type f -o -type l) | sed 's|^\./||' | while read -r f; do
      [ "$(realpath -m "$HOME/$f")" = "$REPO/$p/$f" ] && continue   # already linked to this repo
      park "$HOME/$f"
    done
    (cd "$REPO" && stow -R "$p") && info "linked $p" || fail "stow $p"
  done
  [ -f "$HOME/.zshrc" ] && [ "$(basename "$SHELL")" != zsh ] && \
    gum confirm "Make zsh your login shell?" && chsh -s /usr/bin/zsh
}

# --- 3. agent CLIs (installed the way T3 Code can update them) ----------------
step_agent_clis() {
  say "Claude Code, Codex, OpenCode"
  info "Using each vendor's own installer so T3 Code's 'Update' button works:"
  info "  claude -> native (~/.local/share/claude)       T3 runs: claude update"
  info "  codex  -> standalone (~/.codex/packages)        T3 runs: codex update"
  info "  opencode v2 -> npm prefix (~/.local/share/opencode-v2)  T3 runs: npm i -g --prefix"
  warn "Do NOT install these from the Omarchy AI menu, mise or pacman: those wrappers loop under T3."
  local tools
  tools=$(gum choose --no-limit --selected=claude,codex,opencode claude codex opencode) || return 0
  # Omarchy's mise wrappers (exec mise x ...) shadow the real binaries; keep them out of the way.
  for t in claude codex opencode; do
    if grep -qs "mise x" "$HOME/.local/bin/$t" 2>/dev/null; then park "$HOME/.local/bin/$t"; fi
  done
  for t in $tools; do
    case $t in
      claude)
        curl -fsSL https://claude.ai/install.sh | bash || fail "claude install" ;;
      codex)
        curl -fsSL https://chatgpt.com/codex/install.sh | sh || fail "codex install"
        local cx="$HOME/.codex/packages/standalone/current/bin/codex"
        [ -x "$cx" ] && [ ! -e "$HOME/.local/bin/codex" ] && link "$cx" "$HOME/.local/bin/codex" ;;
      opencode)
        local prefix="$HOME/.local/share/opencode-v2"
        if ! command -v npm >/dev/null; then mise use -g node@lts && eval "$(mise env -s bash)"; fi
        npm install -g --prefix "$prefix" @opencode/cli@latest || { fail "opencode install"; continue; }
        link "$prefix/bin/opencode" "$HOME/.local/bin/opencode" ;;
    esac
  done
  info "Sign in once per tool: run 'claude', 'codex', 'opencode auth login'"
}

# --- 4. AGENTS.md, hooks, skills ----------------------------------------------
step_agent_config() {
  say "Agent instructions, hooks and skills"
  mkdir -p "$HOME/.agents/hooks" "$HOME/.agents/skills" "$HOME/.claude/hooks" "$HOME/.codex" \
           "$HOME/.config/opencode/plugins" "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.config/opencode/skills"

  # One AGENTS.md for all three tools
  install -m 600 "$A/AGENTS.md" "$HOME/.agents/AGENTS.md"
  link "$HOME/.agents/AGENTS.md" "$HOME/.claude/CLAUDE.md"
  link "$HOME/.agents/AGENTS.md" "$HOME/.codex/AGENTS.md"
  link "$HOME/.agents/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"

  # Memory hooks + per-tool hook config
  cp "$A"/hooks/*.py "$HOME/.agents/hooks/"
  cp "$A"/claude/hooks/* "$HOME/.claude/hooks/" && chmod +x "$HOME"/.claude/hooks/*
  park "$HOME/.claude/settings.json"; cp "$A/claude/settings.json" "$HOME/.claude/settings.json"
  park "$HOME/.codex/hooks.json";     cp "$A/codex/hooks.json" "$HOME/.codex/hooks.json"
  [ -f "$A/codex/herdr-agent-state.sh" ] && install -m 755 "$A/codex/herdr-agent-state.sh" "$HOME/.codex/"
  cp "$A"/opencode/plugins/*.js "$HOME/.config/opencode/plugins/"
  if [ -f "$HOME/.config/opencode/opencode.json" ]; then park "$HOME/.config/opencode/opencode.json"; fi
  cp "$A/opencode/opencode.json" "$HOME/.config/opencode/opencode.json"

  # Skills: personal repo first (some skills link into it)
  [ -d "$HOME/Code/parm-skills/.git" ] || git clone -q https://github.com/iamparmjeet/skills.git "$HOME/Code/parm-skills"
  rsync -a "$A/skills/" "$HOME/.agents/skills/"
  while IFS=$'\t' read -r name target; do
    target="${target/\$HOME/$HOME}"
    if [ -e "$target" ]; then link "$target" "$HOME/.agents/skills/$name"
    else warn "skill $name skipped: $target not present yet (re-run this step later)"; fi
  done < "$A/skill-links.tsv"
  # Expose every shared skill to all three tools
  local n=0
  for s in "$HOME"/.agents/skills/*/; do
    s=${s%/}; local name; name=$(basename "$s")
    for d in "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.config/opencode/skills"; do
      [ -e "$d/$name" ] && [ ! -L "$d/$name" ] && continue   # tool-owned skill, leave it
      ln -sfn "$s" "$d/$name"
    done
    n=$((n+1))
  done
  info "$n skills linked into Claude, Codex and OpenCode"

  if gum confirm "Install codebase-memory-mcp (code graph MCP + its hooks)?"; then
    if command -v codebase-memory-mcp >/dev/null; then codebase-memory-mcp update -y
    else warn "get the binary from https://github.com/DeusData/codebase-memory-mcp/releases into ~/.local/bin, then run: codebase-memory-mcp install -y"; fi
  fi
}

# --- 5. Basic Memory shared MCP ------------------------------------------------
step_basic_memory() {
  say "Basic Memory (shared MCP on 127.0.0.1:8765 for all three tools)"
  command -v uv >/dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
  "$HOME/.local/bin/uv" tool install --upgrade basic-memory || { fail "basic-memory install"; return; }
  [ -d "$HOME/basic-memory/.git" ] || git clone -q https://github.com/iamparmjeet/basic-memory.git "$HOME/basic-memory" \
    || fail "clone basic-memory (private: run 'gh auth login' first)"
  mkdir -p "$HOME/.config/basic-memory"
  [ -f "$HOME/.config/basic-memory/config.json" ] || cat > "$HOME/.config/basic-memory/config.json" <<EOF
{"projects": {"main": {"path": "$HOME/basic-memory", "mode": "local"}}, "default_project": "main", "sqlite_synchronous": "NORMAL"}
EOF
  BASIC_MEMORY_CONFIG_DIR="$HOME/.config/basic-memory" "$HOME/.local/bin/basic-memory" reindex >/dev/null 2>&1 || true

  mkdir -p "$HOME/.config/systemd/user"
  cp "$A"/systemd/* "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload
  systemctl --user enable --now basic-memory-shared.service agent-memory-sweep.timer agent-memory-learn.timer \
    || fail "enable memory services"

  # Point each tool at the one shared HTTP server (never a per-chat stdio process)
  python3 -I - "$HOME" <<'PY'
import json, os, sys
home = sys.argv[1]
entry = {"type": "http", "url": "http://127.0.0.1:8765/mcp"}
# T3 launches Claude with CLAUDE_CONFIG_DIR=~/.claude, so both files need it
for f in (f"{home}/.claude/.claude.json", f"{home}/.claude.json"):
    d = json.load(open(f)) if os.path.exists(f) else {}
    d.setdefault("mcpServers", {})["basic-memory"] = entry
    json.dump(d, open(f, "w"), indent=2)
f = f"{home}/.config/opencode/opencode.json"
d = json.load(open(f)) if os.path.exists(f) else {"$schema": "https://opencode.ai/config.json"}
d.setdefault("mcp", {})["basic-memory"] = {"type": "remote", "url": entry["url"], "enabled": True}
json.dump(d, open(f, "w"), indent=2)
PY
  local toml="$HOME/.codex/config.toml"
  mkdir -p "$HOME/.codex"; touch "$toml"
  grep -q '^\[mcp_servers.basic-memory\]' "$toml" || printf '\n[mcp_servers.basic-memory]\nurl = "http://127.0.0.1:8765/mcp"\nenabled = true\n' >> "$toml"
  sleep 3
  if curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8765/mcp | grep -qE '^(200|400|406)$'; then
    info "Basic Memory server is up; Claude, Codex and OpenCode are configured"
  else warn "server not answering yet: check 'systemctl --user status basic-memory-shared'"; fi
}

# --- 6. code repos + secrets ------------------------------------------------------
step_repos() {
  say "Clone my code repos"
  gh auth status >/dev/null 2>&1 || gh auth login || { fail "gh login"; return; }
  local lines chosen
  lines=$(grep -v '^#' "$REPO/repos.txt" | awk 'NF{print $1}')
  chosen=$(gum choose --no-limit --selected="$(echo "$lines" | paste -sd,)" --header "Which repos?" $lines) || return 0
  for r in $chosen; do
    local path; path=$(awk -v r="$r" '$1==r{print $2}' "$REPO/repos.txt")
    if [ -d "$HOME/$path/.git" ]; then info "$path already cloned"; continue; fi
    if [ -d "$HOME/$path" ]; then   # folder holding restored .env files: clone into it
      git clone -q "https://github.com/$r.git" "$HOME/$path.tmp" && cp -an "$HOME/$path.tmp/." "$HOME/$path/" && rm -rf "$HOME/$path.tmp"
    else
      git clone -q "https://github.com/$r.git" "$HOME/$path"
    fi && info "cloned $r -> ~/$path" || fail "clone $r"
  done
}

step_secrets() {
  say "Copy .env files back from the external SSD"
  local src
  src=$(gum input --placeholder "/run/media/$USER/AMAR_WD/Backup/Code" --header "Folder on the SSD that holds your backed-up Code tree") || return 0
  [ -d "$src" ] || { fail "not found: $src"; return; }
  rsync -a --prune-empty-dirs --include='*/' --include='.env*' --include='.dev.vars*' --exclude='*' "$src/" "$HOME/Code/"
  find "$HOME/Code" -name '.env*' -o -name '.dev.vars*' | xargs -r chmod 600
  info "restored $(find "$HOME/Code" \( -name '.env*' -o -name '.dev.vars*' \) | wc -l) secret files (exFAT drops permissions, reset to 600)"
}

# --- menu ------------------------------------------------------------------------
command -v gum >/dev/null || { echo "gum is missing (Omarchy ships it). Install: sudo pacman -S gum"; exit 1; }
gum style --border rounded --padding "0 2" --border-foreground 212 "Parm's Omarchy restore" "repo: $REPO"

STEPS="1 Packages
2 Dotfiles
3 Agent CLIs (Claude, Codex, OpenCode)
4 Agent config (AGENTS.md, hooks, skills)
5 Basic Memory MCP
6 Clone code repos
7 Restore .env secrets from SSD"
CHOSEN=$(echo "$STEPS" | gum choose --no-limit --selected="$(echo "$STEPS" | paste -sd,)" \
  --header "What should I restore? (space toggles, enter starts)") || exit 0

while read -r line; do
  case "${line%% *}" in
    1) step_packages ;;   2) step_dotfiles ;;   3) step_agent_clis ;;
    4) step_agent_config ;; 5) step_basic_memory ;; 6) step_repos ;; 7) step_secrets ;;
  esac
done <<< "$CHOSEN"

echo
[ -d "$BACKUP_DIR" ] && info "Anything I replaced is saved in ${BACKUP_DIR/#$HOME/~}"
if [ ${#FAILED[@]} -gt 0 ]; then
  gum style --foreground 196 --bold "Finished with problems:"; printf '  - %s\n' "${FAILED[@]}"; exit 1
fi
gum style --foreground 82 --bold "All done. Log out and back in to pick up the shell and services."
