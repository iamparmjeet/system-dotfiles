import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).parent
spec = importlib.util.spec_from_file_location("memory", ROOT / "agent-memory.py")
memory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(memory)


class CaptureTests(unittest.TestCase):
    def test_codex_analysis_and_tool_content_are_not_captured(self):
        rows = [
            {"type": "response_item", "payload": {"type": "message", "role": "user", "content": "Help implement student edits"}},
            {"type": "response_item", "payload": {"type": "message", "role": "assistant", "channel": "analysis", "content": "private reasoning"}},
            {"type": "response_item", "payload": {"type": "function_call_output", "output": "private tool output"}},
            {"type": "response_item", "payload": {"type": "message", "role": "assistant", "channel": "final", "content": "Verified the edit contract"}},
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / "source.jsonl"
            path.write_text("\n".join(json.dumps(row) for row in rows))
            users, last, assistants = memory.parse_transcript(str(path))
        self.assertEqual(users, ["Help implement student edits"])
        self.assertEqual(last, "Verified the edit contract")
        self.assertEqual(assistants, [last])

    def test_common_credentials_are_redacted(self):
        credentials = ['sk-proj-' + 'x' * 30, 'ghp_' + 'a' * 30, 'sensitive-value', 'privatepass']
        source = f'{credentials[0]} {credentials[1]} "api_key": "{credentials[2]}" https://user:{credentials[3]}@example.test'
        sanitized = memory.redact(source)
        for credential in credentials:
            self.assertNotIn(credential, sanitized)
        self.assertIn("[REDACTED_SECRET]", sanitized)

    def test_full_ids_preserve_distinct_sessions_and_earlier_decisions(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(memory, "AUTO", tmp):
            for sid in ("ses_same111", "ses_same222"):
                memory.autosave({"session_id": sid, "cwd": str(ROOT), "source_updated": "2026-09-01T12:00:00+05:30", "messages": [
                    {"role": "user", "content": "Implement the editor"},
                    {"role": "assistant", "content": "Decided to preserve inputs on server errors."},
                    {"role": "user", "content": "Proceed"},
                    {"role": "assistant", "content": "Complete. The contract tests passed."},
                ]}, "opencode")
            paths = list(pathlib.Path(tmp).glob("**/*.md"))
            self.assertEqual(len(paths), 2)
            for path in paths:
                self.assertIn("preserve inputs", path.read_text())
                self.assertEqual(memory.frontmatter(str(path))["modified"], "2026-09-01T12:00:00+05:30")

    def test_private_lifeos_is_excluded(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(memory, "AUTO", tmp):
            memory.autosave({"session_id": "private", "cwd": "/home/parm/lifeos/private", "messages": [
                {"role": "user", "content": "Sensitive diary entry"},
            ]}, "claude")
            self.assertEqual(list(pathlib.Path(tmp).glob("**/*.md")), [])


if __name__ == "__main__":
    unittest.main()
