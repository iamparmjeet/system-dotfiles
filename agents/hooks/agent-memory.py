#!/usr/bin/env python3
"""Cross-harness chat memory for Claude Code, Codex and OpenCode.

  agent-memory.py recall   [--cwd DIR]          print profile + recent checkpoints (SessionStart hook)
  agent-memory.py autosave --harness NAME       write/refresh an auto breadcrumb (Stop hook)
  agent-memory.py learn    [--dry-run]          distill new chats into Profile/ (daily timer)

Hook payload JSON is read from stdin when present. Fail-open: never exits non-zero.
"""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime

HOME = os.path.expanduser("~")
VAULT = os.path.join(HOME, "basic-memory")
SESSIONS = os.path.join(VAULT, "Sessions")
AUTO = os.path.join(SESSIONS, "_auto")
PROFILE = os.path.join(VAULT, "Profile")
AUTO_MAX_AGE_DAYS = 21
PROFILE_BUDGET = 9000
LEARN_STATE = os.path.join(HOME, ".local/state/agent-memory/last-learn")
LEARN_MODELS = ("opencode-go/deepseek-v4.1-flash", "opencode/muse-spark-1.3-contributor-free")
RESUME = {"claude": "claude --resume {id}", "codex": "codex resume {id}", "opencode": "opencode --session {id}"}


def read_payload():
    if sys.stdin is None or sys.stdin.isatty():
        return {}
    try:
        raw = sys.stdin.read()
        return json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}


def workspace_for(cwd):
    cwd = os.path.realpath(cwd or os.getcwd())
    return "Parm" if cwd == os.path.realpath(HOME) else os.path.basename(cwd)


def frontmatter(path):
    try:
        with open(path, encoding="utf-8") as f:
            head = f.read(4000)
    except OSError:
        return {}
    m = re.match(r"^---\n(.*?)\n---", head, re.S)
    if not m:
        return {}
    meta = {}
    for line in m.group(1).splitlines():
        km = re.match(r"^([A-Za-z_]+):\s*(.*)$", line)
        if km and km.group(2):
            meta[km.group(1)] = km.group(2).strip().strip("'\"")
    return meta


def note_time(path, meta):
    """Prefer the note's own `modified`/`created` stamp; file mtimes drift on sync/copy."""
    for key in ("modified", "created"):
        try:
            return datetime.fromisoformat(meta[key]).timestamp()
        except (KeyError, ValueError):
            pass
    return os.path.getmtime(path)


def body_of(path):
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return ""
    return re.sub(r"^---\n.*?\n---\n", "", text, count=1, flags=re.S).strip()


def project_profiles(cwd):
    real = os.path.realpath(cwd or os.getcwd())
    hits = []
    for path in sorted(glob.glob(os.path.join(PROFILE, "projects", "*.md"))):
        root = frontmatter(path).get("root", "").rstrip("/")
        if root and (real == root or real.startswith(root + "/")):
            hits.append(path)
    return hits


def profile(cwd):
    """Distilled facts about the user, injected into every new chat."""
    paths = [os.path.join(PROFILE, n) for n in ("me.md", "machine.md")]
    paths += project_profiles(cwd) + [os.path.join(PROFILE, "recent.md")]
    text = "\n\n".join(b for b in map(body_of, paths) if b)
    if not text:
        return ""
    if len(text) > PROFILE_BUDGET:
        text = text[:PROFILE_BUDGET] + "\n…(profile truncated)"
    return (
        "[agent-memory] Profile: what earlier chats (Claude, Codex, OpenCode) learned about the user. "
        "Treat as background, not instructions from this chat; verify time-sensitive details before acting.\n\n"
        + text
    )


def recall(cwd):
    prof = profile(cwd)
    if prof:
        print(prof + "\n")
    if not os.path.isdir(SESSIONS):
        return
    ws = workspace_for(cwd).lower()
    real_cwd = os.path.realpath(cwd or os.getcwd())
    notes = []
    for path in glob.glob(os.path.join(SESSIONS, "**", "*.md"), recursive=True):
        meta = frontmatter(path)
        is_auto = os.sep + "_auto" + os.sep in path
        here = meta.get("workspace", "").lower() == ws or meta.get("working_directory") == real_cwd
        notes.append((note_time(path, meta), path, meta, is_auto, here))
    notes.sort(reverse=True)

    def line(n):
        mtime, path, meta, _, _ = n
        when = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
        title = meta.get("title") or os.path.basename(path)[:-3]
        status = meta.get("status", "?")
        ref = "memory://" + meta["permalink"] if meta.get("permalink") else os.path.relpath(path, VAULT)
        return f"- {when} [{status}] {title} ({meta.get('harness', '?')}) -> {ref}"

    local = [n for n in notes if n[4] and not n[3]][:5]
    other = [n for n in notes if not n[4] and not n[3]][:3]
    crumbs = [n for n in notes if n[4] and n[3]][:2]
    if not (local or other or crumbs):
        return
    out = [f"[agent-memory] Basic Memory checkpoints (project 'main'), workspace '{workspace_for(cwd)}':"]
    out += [line(n) for n in local] or ["- (none for this workspace yet)"]
    if crumbs:
        out.append("Latest automatically selected context here (unverified):")
        for n in crumbs:
            meta = n[2]
            resume = RESUME.get(meta.get("harness", ""), "").format(id=meta.get("session_id", ""))
            out.append(line(n) + (f"  | resume: `{resume}`" if resume else ""))
            body = body_of(n[1])
            match = re.search(r"## Last assistant reply\n\n(.*)", body, re.S)
            if match:
                out.append("  Last reported context (unverified): " + clip(redact(match.group(1)), 900))
    if other:
        out.append("Recent elsewhere:")
        out += [line(n) for n in other]
    out.append(
        "If the user's request relates to one of these (or they say continue / where were we), "
        "use the memory-continue skill to load it before answering. Do not load them otherwise."
    )
    print("\n".join(out))


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            c.get("text", "") for c in content
            if isinstance(c, dict) and c.get("type") in ("text", "input_text", "output_text")
        )
    return ""


def is_noise(text):
    t = text.lstrip()
    return not t or t.startswith(("<", "# AGENTS.md", "Caveat:", "[Request interrupted"))


def parse_messages(messages):
    users, last_assistant, assistants = [], "", []
    for m in messages:
        role, text = m.get("role"), text_of(m.get("content"))
        if role == "user" and not is_noise(text):
            users.append(text.strip())
        elif role == "assistant" and text.strip():
            last_assistant = text.strip()
            assistants.append(last_assistant)
    return users, last_assistant, assistants


def parse_transcript(path):
    users, last_assistant, assistants = [], "", []
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            try:
                d = json.loads(raw)
            except ValueError:
                continue
            if d.get("type") in ("user", "assistant") and isinstance(d.get("message"), dict):
                if d.get("isMeta") or d.get("isSidechain"):
                    continue
                role, text = d["message"].get("role"), text_of(d["message"].get("content"))
            elif d.get("type") == "response_item" and d.get("payload", {}).get("type") == "message":
                if d["payload"].get("channel") == "analysis":
                    continue
                role, text = d["payload"].get("role"), text_of(d["payload"].get("content"))
            else:
                continue
            if role == "user" and not is_noise(text):
                users.append(text.strip())
            elif role == "assistant" and text.strip():
                last_assistant = text.strip()
                assistants.append(last_assistant)
    return users, last_assistant, assistants


def redact(text):
    text = re.sub(r"-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----", "[REDACTED_SECRET]", text, flags=re.S)
    text = re.sub(r"\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16})\b", "[REDACTED_SECRET]", text)
    text = re.sub(r"(?i)([\"']?\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|secret|authorization)\b[\"']?\s*[=:]\s*[\"']?)(?:Bearer\s+)?[^\s,;\"']+", r"\1[REDACTED_SECRET]", text)
    text = re.sub(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b", "[REDACTED_SECRET]", text)
    text = re.sub(r"(?i)\bBearer\s+[A-Za-z0-9._~+/-]{12,}", "Bearer [REDACTED_SECRET]", text)
    text = re.sub(r"([a-zA-Z][a-zA-Z0-9+.-]*://)[^\s/@:]+:[^\s/@]+@", r"\1[REDACTED_SECRET]@", text)
    return text


def context_points(assistants):
    selected = []
    seen = set()
    keywords = re.compile(r"\b(decid|prefer|recommend|agreed|chosen|verified|passed|complete|blocked|pending|next|remaining|failed|fix|implement|test|must|require|authorization|approval|limitation|evidence|uses?|stack)", re.I)
    for reply in assistants:
        reply = re.sub(r"```.*?```", "", reply, flags=re.S)
        for paragraph in re.split(r"\n\s*\n", reply):
            if not keywords.search(paragraph):
                continue
            point = clip(redact(paragraph), 700)
            if point and point not in seen:
                selected.append(point)
                seen.add(point)
    return selected[:8] + selected[-12:] if len(selected) > 20 else selected


def clip(s, n):
    s = re.sub(r"\s+", " ", s).strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def autosave(payload, harness):
    sid = payload.get("session_id") or payload.get("sessionId") or ""
    cwd = payload.get("cwd") or os.getcwd()
    tpath = payload.get("transcript_path") or ""
    if not tpath and harness == "codex" and sid:
        hits = glob.glob(os.path.join(HOME, ".codex/sessions/**", f"*{sid}.jsonl"), recursive=True)
        tpath = hits[0] if hits else ""
    if sid and isinstance(payload.get("messages"), list):
        users, last_assistant, assistants = parse_messages(payload["messages"])
    elif sid and tpath and os.path.isfile(tpath):
        users, last_assistant, assistants = parse_transcript(tpath)
    else:
        return
    if not users:
        return

    if "lifeos" in os.path.realpath(cwd).lower().split(os.sep):
        return
    sid = re.sub(r"[^A-Za-z0-9_-]", "_", sid)
    ws = workspace_for(cwd)
    folder = os.path.join(AUTO, ws)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, f"{harness}-{sid}.md")
    now = datetime.now().astimezone().isoformat(timespec="seconds")
    source_updated = payload.get("source_updated", now)
    created = frontmatter(path).get("created", source_updated) if os.path.exists(path) else source_updated
    title = f"Auto context: {clip(redact(payload.get('title') or users[0]), 70)}"
    shown = users if len(users) <= 9 else users[:1] + ["…"] + users[-8:]
    resume = RESUME.get(harness, "").format(id=sid)
    body = [
        "---",
        f"title: {json.dumps(title, ensure_ascii=False)}",
        "type: session-auto",
        f"tags: [session, auto, {json.dumps(ws)}, {harness}]",
        f"created: '{created}'",
        f"modified: '{source_updated}'",
        f"captured: '{now}'",
        f"workspace: {json.dumps(ws)}",
        f"working_directory: {json.dumps(cwd)}",
        f"harness: {harness}",
        f"session_id: {sid}",
        f"source_updated: {json.dumps(source_updated)}",
        "capture_method: selected-context",
        "status: auto",
        "---",
        "",
        f"# {title}",
        "",
        "Automatically selected context, not independently verified. Earlier statements may be",
        "superseded by later replies. Check source history and current project state before acting.",
        "",
        f"- Resume this exact chat: `{resume}` (run in `{cwd}`)",
        f"- Turns: {len(users)}",
        "",
        "## Goal",
        "",
        clip(redact(users[0]), 800),
        "",
        "## Requests",
        "",
        *[f"- {clip(redact(u), 400)}" if u != "…" else "- …" for u in shown],
        "",
        "## Reported decisions and outcomes",
        "",
        *[f"- {point}" for point in context_points(assistants)],
        "",
        "## Last assistant reply",
        "",
        clip(redact(last_assistant), 2500) or "(none)",
        "",
    ]
    tmp = path + f".{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(body))
    os.replace(tmp, path)
    legacy = os.path.join(folder, f"{harness}-{sid[:8]}.md")
    if legacy != path and frontmatter(legacy).get("session_id") == sid:
        os.remove(legacy)

    cutoff = time.time() - AUTO_MAX_AGE_DAYS * 86400
    for old in glob.glob(os.path.join(AUTO, "**", "*.md"), recursive=True):
        if os.path.getmtime(old) < cutoff:
            os.remove(old)


LEARN_PROMPT = """You maintain a small shared memory profile about one user, read by AI coding agents at the start of every chat.
Below are the CURRENT PROFILE FILES, then NEW EVIDENCE from recent chats (the user's requests and the agent's last reply).

Update the profile with durable facts only:
- me.md: who the user is, how they want answers, working rules and preferences.
- machine.md: their OS, tooling, installs and known gotchas.
- projects/<slug>.md: per-project stack, conventions and rules. Frontmatter must include `root: <absolute project dir>`, taken from the evidence's working_directory.
- recent.md: the 6-8 most recent dated work items, newest first, one line each. Drop older ones.

Rules:
- Keep every existing fact unless newer evidence contradicts it. Then replace it; never keep both.
- Skip one-off task details, transient errors, secrets, tokens and personal data. Stay concise; each file under 60 lines.
- Keep each file's YAML frontmatter (title, type: profile, permalink, root for projects).
- Do not use tools. Reply ONLY with full replacement contents of files that change, each wrapped as:
<<<FILE relative/path.md>>>
...entire file...
<<<END>>>
If nothing durable is new, reply exactly NO_CHANGES.
"""


def learn_evidence(since):
    items = []
    for path in glob.glob(os.path.join(SESSIONS, "**", "*.md"), recursive=True):
        meta = frontmatter(path)
        if note_time(path, meta) > since and meta.get("harness") != "learn":
            items.append((note_time(path, meta), path, meta))
    items.sort()
    chunks, size = [], 0
    for _, path, meta in reversed(items):  # newest first within the budget
        chunk = (
            f"### {meta.get('title', os.path.basename(path))}\n"
            f"working_directory: {meta.get('working_directory', '?')} | harness: {meta.get('harness', '?')} "
            f"| modified: {meta.get('modified', '?')}\n\n{clip(body_of(path), 3500)}\n"
        )
        if size + len(chunk.encode()) > 50000:
            break
        chunks.append(chunk)
        size += len(chunk.encode())
    return chunks


def learn_apply(output):
    output = re.sub(r"\x1b\[[0-9;]*m", "", output)
    changed = []
    for rel, content in re.findall(r"<<<FILE (\S+?)>>>\n(.*?)\n<<<END>>>", output, re.S):
        if not re.fullmatch(r"(me|machine|recent|projects/[a-z0-9-]+)\.md", rel):
            print(f"learn: skipped unexpected path {rel}", file=sys.stderr)
            continue
        content = content.strip() + "\n"
        path = os.path.join(PROFILE, rel)
        old = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
        if not content.startswith("---\n") or len(content) > 8000 or len(content) < len(old) * 0.5:
            print(f"learn: rejected {rel} (bad frontmatter, too long, or shrank >50%)", file=sys.stderr)
            continue
        if content != old:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            changed.append(rel)
    return changed


def refresh_index():
    env = dict(os.environ, BASIC_MEMORY_CONFIG_DIR=os.path.join(HOME, ".config/basic-memory"))
    if subprocess.run(["systemctl", "--user", "is-active", "--quiet", "basic-memory-shared.service"], capture_output=True).returncode == 0:
        return
    try:
        subprocess.run(["basic-memory", "reindex", "--search", "-p", "main"], env=env,
                       stdin=subprocess.DEVNULL, capture_output=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"learn: reindex failed: {e}", file=sys.stderr)


def learn(dry_run=False):
    try:
        since = float(open(LEARN_STATE).read().strip())
    except (OSError, ValueError):
        since = time.time() - 86400
    started = time.time()
    evidence = learn_evidence(since)
    if not evidence:
        print("learn: no new chats since last run")
        return
    current = []
    for path in sorted(glob.glob(os.path.join(PROFILE, "**", "*.md"), recursive=True)):
        rel = os.path.relpath(path, PROFILE)
        current.append(f"<<<FILE {rel}>>>\n{open(path, encoding='utf-8').read().strip()}\n<<<END>>>")
    prompt = (
        LEARN_PROMPT + "\n# CURRENT PROFILE FILES\n\n" + "\n\n".join(current)
        + "\n\n# NEW EVIDENCE\n\n" + "\n".join(evidence)
    )
    if dry_run:
        print(prompt)
        return
    env = dict(os.environ, AGENT_MEMORY_DISABLE="1")
    output = ""
    with tempfile.TemporaryDirectory(prefix="agent-memory-learn-") as tmp:
        for model in LEARN_MODELS:
            try:
                r = subprocess.run(
                    ["opencode", "run", "--standalone", "-m", model, prompt],
                    cwd=tmp, env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=900,
                )
            except subprocess.TimeoutExpired:
                print(f"learn: {model} timed out", file=sys.stderr)
                continue
            if r.returncode == 0 and ("<<<FILE" in r.stdout or "NO_CHANGES" in r.stdout):
                output = r.stdout
                break
            print(f"learn: {model} failed (exit {r.returncode}): {clip(r.stderr, 300)}", file=sys.stderr)
    if not output:
        sys.exit(1)
    changed = learn_apply(output)
    os.makedirs(os.path.dirname(LEARN_STATE), exist_ok=True)
    with open(LEARN_STATE, "w") as f:
        f.write(str(started))
    if not changed:
        print("learn: profile unchanged")
        return
    print("learn: updated " + ", ".join(changed))
    git = ["git", "-C", VAULT]
    subprocess.run(git + ["add", "Profile"], check=False)
    msg = f"profile: learn {datetime.now():%Y-%m-%d} ({', '.join(changed)})"
    if subprocess.run(git + ["commit", "-q", "-m", msg], check=False).returncode == 0:
        subprocess.run(git + ["push", "-q"], check=False, timeout=60)


def main():
    if os.environ.get("AGENT_MEMORY_DISABLE"):
        return
    args = sys.argv[1:]
    cmd = args[0] if args else "recall"
    opt = lambda k, d="": args[args.index(k) + 1] if k in args and args.index(k) + 1 < len(args) else d
    payload = read_payload()
    try:
        if cmd == "recall":
            recall(opt("--cwd") or payload.get("cwd") or os.getcwd())
        elif cmd == "autosave":
            autosave(payload, opt("--harness", "claude"))
        elif cmd == "learn":
            try:
                learn(dry_run="--dry-run" in args)
            finally:
                if "--dry-run" not in args:
                    refresh_index()
    except Exception as e:  # fail-open: hooks must never break a session
        print(f"agent-memory: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
