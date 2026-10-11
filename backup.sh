#!/usr/bin/env bash
# Snapshot this machine into the repo so restore.sh can rebuild it.
# Safe to re-run any time before a reset; review `git diff` and commit after.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
A="$REPO/agents"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# --- packages --------------------------------------------------------------
say "Package list"
omarchy_pkgs=$(cat /usr/share/omarchy/install/omarchy-*.packages 2>/dev/null | grep -v '^#' | awk '{print $1}' | sort -u)
comm -23 <(pacman -Qqe | sort) <(echo "$omarchy_pkgs") > "$REPO/packages/.installed-snapshot.txt"
listed=$(cat "$REPO"/packages/*.txt "$REPO"/packages/skip.list 2>/dev/null | sed 's/#.*//' | awk 'NF{print $1}' | sort -u)
new=$(comm -23 "$REPO/packages/.installed-snapshot.txt" <(echo "$listed"))
if [ -n "$new" ]; then
  echo "  Installed but not in any packages/*.txt (add them to a group or to skip.list):"
  echo "$new" | sed 's/^/    /'
else
  echo "  every installed extra package is already grouped"
fi

# --- agent instructions, hooks, services -----------------------------------
say "Agent config"
mkdir -p "$A"/{hooks,systemd,claude/hooks,codex,opencode/plugins,skills}
cp "$HOME/.agents/AGENTS.md" "$A/AGENTS.md"
for f in agent-memory.py agent-memory-sweep.py memory-http.py test_agent_memory.py; do
  [ -f "$HOME/.agents/hooks/$f" ] && cp "$HOME/.agents/hooks/$f" "$A/hooks/"
done
for u in basic-memory-shared.service agent-memory-learn.service agent-memory-learn.timer \
         agent-memory-sweep.service agent-memory-sweep.timer; do
  [ -f "$HOME/.config/systemd/user/$u" ] && cp "$HOME/.config/systemd/user/$u" "$A/systemd/"
done
cp "$HOME/.claude/settings.json" "$A/claude/settings.json"
cp "$HOME"/.claude/hooks/* "$A/claude/hooks/" 2>/dev/null || true
cp "$HOME/.codex/hooks.json" "$A/codex/hooks.json"
[ -f "$HOME/.codex/herdr-agent-state.sh" ] && cp "$HOME/.codex/herdr-agent-state.sh" "$A/codex/"
cp "$HOME/.config/opencode/opencode.json" "$A/opencode/opencode.json"
cp "$HOME"/.config/opencode/plugins/*.js "$A/opencode/plugins/" 2>/dev/null || true

# --- skills ----------------------------------------------------------------
# Real skill folders are vendored; symlinks are recorded and recreated on restore.
say "Skills"
rsync -a --delete --exclude='node_modules' \
  $(find "$HOME/.agents/skills" -mindepth 1 -maxdepth 1 -type d ! -type l -printf '%p ') "$A/skills/"
find "$HOME/.agents/skills" -mindepth 1 -maxdepth 1 -type l -printf '%f\t%l\n' \
  | sed "s|$HOME|\$HOME|g" | sort > "$A/skill-links.tsv"
echo "  $(find "$A/skills" -mindepth 1 -maxdepth 1 -type d | wc -l) vendored, $(wc -l < "$A/skill-links.tsv") linked"

# --- secret guard: this repo is public ------------------------------------
say "Secret scan"
pat='(sk-[A-Za-z0-9_-]{20,}|sk-ant-|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
if hits=$(grep -rIlE "$pat" "$A" --exclude=agent-memory.py --exclude=test_agent_memory.py 2>/dev/null); then
  echo "  POSSIBLE SECRETS, do not commit until checked:"; echo "$hits" | sed 's/^/    /'; exit 1
fi
echo "  clean"
say "Done. Review with: git -C $REPO status"
