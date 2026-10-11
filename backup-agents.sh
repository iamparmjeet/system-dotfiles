#!/usr/bin/env bash
# Back up agent + T3 data to the SSD as tar.zst archives with consistent SQLite snapshots.
set -uo pipefail
OUT="${1:?usage: backup-agents.sh <folder on SSD>}"; mkdir -p "$OUT"/{agents,t3,basic-memory}
log(){ echo "[$(date +%T)] $*"; }

# snapshot every sqlite db under $1 (depth<=2) into $2, print relative names for tar --exclude
snap() {
  local src=$1 dst=$2; mkdir -p "$dst"
  find "$src" -maxdepth 2 -type f \( -name '*.sqlite' -o -name '*.db' \) | while read -r db; do
    rel=${db#"$src"/}; mkdir -p "$dst/$(dirname "$rel")"
    if sqlite3 "$db" ".timeout 20000" ".backup '$dst/$rel'" 2>/dev/null; then
      ok=$(sqlite3 "$dst/$rel" 'PRAGMA quick_check;' 2>&1 | head -1); log "  db $rel -> $ok"
    else log "  db $rel FAILED"; fi
  done
}
pack() { # name, base dir, dir, extra tar args...
  local name=$1 base=$2 dir=$3; shift 3
  tar -C "$base" --exclude='*.sqlite' --exclude='*.db' --exclude='*-wal' --exclude='*-shm' "$@" \
      -cf - "$dir" 2>>"$OUT/tar-warnings.log" | zstd -q -T0 -10 -o "$OUT/$name.tar.zst" -f
  log "  $name.tar.zst $(du -h "$OUT/$name.tar.zst" | cut -f1)"
}

log "Claude"
snap ~/.claude "$OUT/agents/claude-db"
pack agents/claude ~ .claude --exclude=.claude/cache --exclude=.claude/plugins/cache
cp ~/.claude.json "$OUT/agents/claude.json"

log "Codex"
snap ~/.codex "$OUT/agents/codex-db"
pack agents/codex ~ .codex --exclude=.codex/packages --exclude=.codex/.tmp --exclude=.codex/cache --exclude=.codex/plugins/cache --exclude='.codex/logs_*'

log "OpenCode"
snap ~/.local/share/opencode "$OUT/agents/opencode-db"
pack agents/opencode-data ~/.local/share opencode --exclude=opencode/log
pack agents/opencode-config ~/.config opencode --exclude=opencode/node_modules
tar -C ~/.local/state -cf - opencode | zstd -q -o "$OUT/agents/opencode-state.tar.zst" -f
[ -d ~/.pi ] && pack agents/pi ~ .pi

log "T3 Code"
snap ~/.t3/userdata "$OUT/t3/userdata-db"
pack t3/t3-userdata ~/.t3 userdata --exclude=userdata/logs --exclude='userdata/*.cow-backup' --exclude=userdata/server-browser
pack t3/t3-misc ~ .t3 --exclude=.t3/userdata --exclude=.t3/tools --exclude=.t3/worktrees
for d in t3code t3code-v2; do
  pack "t3/desktop-$d" ~/.config "$d" --exclude="$d/Cache" --exclude="$d/Code Cache" --exclude="$d/GPUCache" --exclude="$d/DawnWebGPUCache" --exclude="$d/DawnGraphiteCache" --exclude="$d/Partitions/*/Cache" --exclude="$d/Partitions/*/Code Cache"
done
tar -C ~/.local/share -cf - t3code | zstd -q -o "$OUT/t3/local-share-t3code.tar.zst" -f
cp ~/.local/bin/t3 ~/.local/bin/t3-db-nocow ~/.local/bin/t3-stall-watch "$OUT/t3/" 2>/dev/null

log "Basic Memory"
pack basic-memory/basic-memory-notes ~ basic-memory
snap ~/.config/basic-memory "$OUT/basic-memory/config-db"
pack basic-memory/basic-memory-config ~/.config basic-memory --exclude=basic-memory/fastembed_cache --exclude='basic-memory/*.log'
tar -C ~ -cf - .agents | zstd -q -o "$OUT/agents/dot-agents.tar.zst" -f

log "Verify archives"
for f in $(find "$OUT" -name '*.tar.zst'); do zstd -tq "$f" && echo "  ok $(basename "$f")" || echo "  CORRUPT $f"; done
sync; du -sh "$OUT"; log DONE
