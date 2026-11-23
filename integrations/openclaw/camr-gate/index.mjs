// CAMR's gate for OpenClaw (D-108). After a tool that can change files runs (edit, write, apply_patch, exec), this
// runs `camr check <vault> --json`. If the change in the linked code rests on a decision kept in CAMR's Ledger that
// has not been shown yet (exit 2), or CAMR says the change breaks one (exit 3), the decisions and their reasons are
// added to that tool's result, with what the model must do, so the model reads them before it goes on.
// Why after the tool and not at the end of the turn: OpenClaw's end-of-turn hook (before_agent_finalize) can ask for a
// revision, but OpenClaw ignores that request once a tool with side effects has run, which is every edit.
// Each change is held once: CAMR records a change as shown when it checks it, and this plugin also remembers what it
// already said. Settings (camr, vault, stateDir) come from plugins.entries.camr-gate.config in openclaw.json, which
// `camr connect openclaw <vault> --write` writes. No dependencies.
import { execFile } from "node:child_process";
import { appendFileSync } from "node:fs";

const NOTE = "CAMR held your reply: this change rests on a decision kept in the Ledger, and it had not been checked against it. " +
  "Before you finish, tell the person which decision this change touches and whether it goes against it, in plain words. " +
  "If it goes against a decision, put the code back as it was and ask the person whether they want to overturn that decision first.";
const BROKEN = "CAMR's check says this change breaks a decision kept in the Ledger.";
const CHANGING_TOOLS = new Set(["edit", "write", "apply_patch", "exec", "bash", "shell", "multi_edit"]);
const MOST = 3;

function log(entry) {
  const file = process.env.CAMR_GATE_LOG;
  if (!file) return;
  try { appendFileSync(file, JSON.stringify({ program: "openclaw", at: new Date().toISOString(), ...entry }) + "\n"); } catch {}
}

// Runs the check. Resolves to { code, report } or null when it could not run; a gate that cannot run never blocks.
function check(config) {
  return new Promise((resolve) => {
    const env = { ...process.env };
    if (config.stateDir) env.CAMR_STATE_DIR = config.stateDir;
    execFile(config.camr || "camr", ["check", config.vault, "--json"], { timeout: 12000, maxBuffer: 8 << 20, env },
      (error, stdout) => {
        const code = error ? (typeof error.code === "number" ? error.code : -1) : 0;
        let report = null;
        try { report = JSON.parse(String(stdout)); } catch {}
        resolve(report ? { code, report } : null);
      });
  });
}

function heldMessage(result) {
  if (!result) return null;
  const exit = typeof result.report.exit === "number" ? result.report.exit : result.code;
  if (![2, 3].includes(result.code) && ![2, 3].includes(exit)) return null;
  const broken = result.code === 3 || exit === 3;
  return (broken ? BROKEN + "\n\n" : "") + (result.report.text || "") + "\n\n" + NOTE;
}

export default {
  id: "camr-gate",
  name: "CAMR gate",
  register(api) {
    const config = api.pluginConfig || {};
    if (!config.vault) return;
    const said = [];
    api.registerAgentToolResultMiddleware(async (event) => {
      // Never throw: OpenClaw replaces the tool's output when a middleware fails.
      try {
        if (!event || !CHANGING_TOOLS.has(event.toolName) || said.length >= MOST) return undefined;
        const result = await check(config);
        const message = heldMessage(result);
        log({ event: "after_tool", tool: event.toolName, exit: result ? result.code : null, held: Boolean(message) });
        const key = result && (result.report.fingerprint || result.report.text);
        if (!message || said.includes(key)) return undefined;
        said.push(key);
        log({ event: "held", tool: event.toolName, fingerprint: result.report.fingerprint, decisions: (result.report.decisions || []).map((d) => d.id) });
        const previous = (event.result && Array.isArray(event.result.content)) ? event.result.content : [];
        return { result: { ...event.result, content: [...previous, { type: "text", text: "\n\n" + message }] } };
      } catch {
        return undefined;
      }
    }, { runtimes: ["openclaw"] });
  },
};
