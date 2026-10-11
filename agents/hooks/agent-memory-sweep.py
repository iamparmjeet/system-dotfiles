#!/usr/bin/env python3
import argparse
import base64
import collections
import fcntl
import importlib.util
import json
import os
import pathlib
import urllib.parse
import urllib.request
from datetime import datetime

ROOT = pathlib.Path.home()
STATE_DIR = ROOT / ".local/state/agent-memory"
STATE_PATH = STATE_DIR / "sweep-state.json"
spec = importlib.util.spec_from_file_location("agent_memory", ROOT / ".agents/hooks/agent-memory.py")
memory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(memory)


def api(path):
    service = json.loads((ROOT / ".local/state/opencode/service.json").read_text())
    url = service["url"]
    if urllib.parse.urlparse(url).hostname not in ("127.0.0.1", "localhost", "::1"):
        raise RuntimeError("History capture only connects to the local OpenCode service")
    credentials = base64.b64encode(("opencode:" + service["password"]).encode()).decode()
    request = urllib.request.Request(url + path, headers={"Authorization": "Basic " + credentials})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = json.load(response)
    if "data" not in data or not isinstance(data["data"], list):
        raise RuntimeError("Unexpected OpenCode API response")
    return data


def pages(path, kind=None):
    cursor = None
    seen = set()
    while True:
        query = {"limit": "50"}
        if kind:
            query["type"] = kind
        query["cursor" if cursor else "order"] = cursor or "asc"
        response = api(path + "?" + urllib.parse.urlencode(query))
        yield from response["data"]
        cursor = (response.get("cursor") or {}).get("next")
        if not cursor:
            return
        if cursor in seen:
            raise RuntimeError("Repeated OpenCode pagination cursor")
        seen.add(cursor)


def metadata(path, harness):
    session = {"session_id": path.stem, "cwd": ""}
    with path.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            try:
                item = json.loads(line)
            except ValueError:
                continue
            if harness == "codex" and item.get("type") == "session_meta":
                payload = item.get("payload", {})
                session.update(session_id=payload.get("id", path.stem), cwd=payload.get("cwd", ""))
                break
            if harness == "claude" and item.get("cwd"):
                session.update(session_id=item.get("sessionId", path.stem), cwd=item["cwd"])
                break
    return session


def excluded(cwd, users):
    return (not cwd or "lifeos" in pathlib.Path(cwd).parts or not users
            or users[0].startswith("You maintain a small shared memory profile"))


def sweep(backfill=False, native_only=False):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with (STATE_DIR / "sweep.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("sweep: another capture is running")
            return
        try:
            state = json.loads(STATE_PATH.read_text())
        except (OSError, ValueError):
            state = {}
        counts = collections.Counter()
        failures = []
        sources = [("codex", ROOT / ".codex/sessions"), ("codex", ROOT / ".codex/archived_sessions"),
                   ("claude", ROOT / ".claude/projects")]
        for harness, directory in sources:
            for path in sorted(directory.glob("**/*.jsonl")):
                counts[harness + "_files"] += 1
                key = str(path)
                stat = path.stat()
                signature = [stat.st_mtime_ns, stat.st_size]
                if not backfill and state.get(key) == signature:
                    counts[harness + "_unchanged"] += 1
                    continue
                try:
                    session = metadata(path, harness)
                    users, _, _ = memory.parse_transcript(str(path))
                    if excluded(session["cwd"], users):
                        counts[harness + "_excluded"] += 1
                    else:
                        session.update(transcript_path=str(path), source_updated=datetime.fromtimestamp(stat.st_mtime).astimezone().isoformat())
                        memory.autosave(session, harness)
                        counts[harness + "_captured"] += 1
                    state[key] = signature
                except Exception as error:
                    failures.append({"harness": harness, "source": str(path), "error": type(error).__name__})
        if not native_only:
            try:
                for session in pages("/api/session"):
                    sid = session["id"]
                    counts["opencode_sessions"] += 1
                    signature = session.get("time", {}).get("updated")
                    key = "opencode:" + sid
                    if not backfill and state.get(key) == signature:
                        counts["opencode_unchanged"] += 1
                        continue
                    try:
                        messages = []
                        for role in ("user", "assistant"):
                            for message in pages(f"/api/session/{sid}/message", role):
                                messages.append({"role": role, "content": memory.text_of(message.get("content") or message.get("text") or message.get("parts", []))[:12000],
                                                 "time": message.get("time", {}).get("created", 0)})
                        messages.sort(key=lambda message: message["time"])
                        users, _, _ = memory.parse_messages(messages)
                        cwd = (session.get("location") or {}).get("directory") or session.get("directory", "")
                        if excluded(cwd, users):
                            counts["opencode_excluded"] += 1
                        else:
                            memory.autosave({"session_id": sid, "cwd": cwd, "messages": messages,
                                             "title": session.get("title", ""),
                                             "source_updated": datetime.fromtimestamp((signature or 0) / 1000).astimezone().isoformat()}, "opencode")
                            counts["opencode_captured"] += 1
                        state[key] = signature
                    except Exception as error:
                        failures.append({"harness": "opencode", "source": sid, "error": type(error).__name__})
            except FileNotFoundError:
                counts["opencode_service_down"] += 1
            except Exception as error:
                failures.append({"harness": "opencode", "source": "session-list", "error": type(error).__name__})
        tmp = STATE_PATH.with_suffix(".tmp")
        tmp.write_text(json.dumps(state))
        tmp.replace(STATE_PATH)
        report = {"time": datetime.now().astimezone().isoformat(), "counts": dict(counts), "failures": failures}
        (STATE_DIR / "sweep-report.json").write_text(json.dumps(report, indent=2))
        if backfill:
            (STATE_DIR / "backfill-report.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report))
        if failures:
            raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--backfill", action="store_true")
    parser.add_argument("--native-only", action="store_true")
    args = parser.parse_args()
    sweep(args.backfill, args.native_only)
