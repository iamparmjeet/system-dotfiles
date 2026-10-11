// Cross-harness chat memory for OpenCode v2: the same ~/.agents/hooks/agent-memory.py
// that Claude Code and Codex call from SessionStart/Stop hooks.
//   - first request of a session: inject `recall` output (profile + checkpoints) into the system prompt
//   - every request: rewrite the session's auto breadcrumb from the conversation so far
// One-shot python processes only; nothing keeps running between turns.
// Plain default export (no @opencode/plugin import): the v2 server only validates { id, setup }.

import { spawn } from "node:child_process";
import os from "node:os";

const HOOK = `${os.homedir()}/.agents/hooks/agent-memory.py`;

function run(args, input) {
  return new Promise((resolve) => {
    const child = spawn("python3", ["-I", HOOK, ...args], {
      stdio: ["pipe", "pipe", "ignore"],
    });
    let out = "";
    const timer = setTimeout(() => child.kill(), 10_000);
    child.stdout.on("data", (d) => (out += d.toString()));
    child.on("error", () => resolve(""));
    child.on("close", () => {
      clearTimeout(timer);
      resolve(out.trim());
    });
    child.stdin.end(input ?? "");
  });
}

export default {
  id: "agent-memory",
  async setup(ctx) {
    // `agent-memory.py learn` runs OpenCode itself; don't recall into or autosave that session.
    if (process.env.AGENT_MEMORY_DISABLE) return;

    const recalled = new Map(); // sessionID -> recall text, fixed per session to keep prompt caching stable
    const saving = new Map(); // sessionID -> pending autosave, so writes don't overlap

    async function directoryOf(sessionID) {
      try {
        const res = await ctx.session.get({ sessionID });
        const session = res?.data ?? res;
        return session?.location?.directory ?? ctx.location?.directory ?? process.cwd();
      } catch {
        return ctx.location?.directory ?? process.cwd();
      }
    }

    await ctx.session.hook("context", async (event) => {
      const sessionID = event.sessionID;
      if (!recalled.has(sessionID)) {
        const cwd = await directoryOf(sessionID);
        recalled.set(sessionID, { cwd, text: await run(["recall", "--cwd", cwd]) });
      }
      const { cwd, text } = recalled.get(sessionID);
      if (text) event.system.push({ type: "text", text });

      const messages = event.messages.map((m) => ({
        role: m.role ?? m.type,
        content: m.content ?? m.text ?? [],
      }));
      const payload = JSON.stringify({ session_id: sessionID, cwd, messages });
      const previous = saving.get(sessionID) ?? Promise.resolve();
      saving.set(
        sessionID,
        previous.then(() => run(["autosave", "--harness", "opencode"], payload)),
      );
    });
  },
};
