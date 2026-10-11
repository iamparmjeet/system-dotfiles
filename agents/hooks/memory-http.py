#!/usr/bin/env python3
import json
import sys
import urllib.request

URL = "http://127.0.0.1:8765/mcp"


class MemoryClient:
    def __init__(self, name="agent-memory"):
        self.session = None
        self.counter = 0
        self.request("initialize", {
            "protocolVersion": "2025-03-26", "capabilities": {},
            "clientInfo": {"name": name, "version": "1"},
        })
        self.request("notifications/initialized", notification=True)

    def request(self, method, params=None, notification=False):
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if self.session:
            headers["Mcp-Session-Id"] = self.session
        payload = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            payload["params"] = params
        if not notification:
            self.counter += 1
            payload["id"] = self.counter
        req = urllib.request.Request(URL, data=json.dumps(payload).encode(), headers=headers)
        with urllib.request.urlopen(req, timeout=60) as response:
            self.session = response.headers.get("Mcp-Session-Id", self.session)
            raw = response.read().decode()
        if not raw.strip():
            return {}
        if raw.lstrip().startswith("{"):
            result = json.loads(raw)
        else:
            messages = [json.loads(line[5:].strip()) for line in raw.splitlines() if line.startswith("data:")]
            result = next((m for m in messages if m.get("id") == payload.get("id")), {})
        if "error" in result:
            raise RuntimeError(result["error"])
        return result.get("result", {})

    def call(self, name, arguments):
        result = self.request("tools/call", {"name": name, "arguments": arguments})
        if result.get("isError"):
            raise RuntimeError(result)
        return result

    def close(self):
        if self.session:
            req = urllib.request.Request(URL, method="DELETE", headers={"Mcp-Session-Id": self.session})
            with urllib.request.urlopen(req, timeout=10):
                pass
            self.session = None


if __name__ == "__main__":
    client = MemoryClient()
    try:
        if len(sys.argv) > 1:
            print(json.dumps(client.call(sys.argv[1], json.loads(sys.argv[2] if len(sys.argv) > 2 else "{}"))))
        else:
            result = client.request("tools/list")
            print(json.dumps([t["name"] for t in result.get("tools", [])]))
    finally:
        client.close()
