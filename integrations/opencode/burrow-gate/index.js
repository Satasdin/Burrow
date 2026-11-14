// Burrow's gate for OpenCode (D-108). When the agent is about to go idle (it has finished its turn), this runs
// `burrow check <vault> --json`. If the change in the linked code rests on a decision kept in Burrow's Ledger that has
// not been shown yet (exit 2), or Burrow says the change breaks one (exit 3), the decisions and their reasons go back
// into the session as a message the model must answer, and OpenCode runs another step. Each change is held once:
// Burrow records a change as shown when it checks it, and this file also remembers what it already said per session.
// One follow-up, once per change: if the model stops again with the held change still in the files (in the D-108 runs
// gemma4:12b twice wrote "I have reverted the change" and had not), it is told so, plainly, once.
// Settings come from burrow-gate.json beside this file, which `burrow connect opencode <vault> --write` writes.
// No dependencies: OpenCode 2.x loads a plain object with an id and a setup function.
import { execFile } from "node:child_process";
import { appendFileSync, readFileSync } from "node:fs";

const NOTE = "Burrow held your reply: this change rests on a decision kept in the Ledger, and it had not been checked against it. " +
  "Before you finish, tell the person which decision this change touches and whether it goes against it, in plain words. " +
  "If it goes against a decision, put the code back as it was and ask the person whether they want to overturn that decision first.";
const BROKEN = "Burrow's check says this change breaks a decision kept in the Ledger.";
const MOST_PER_SESSION = 3;

// What the follow-up says: the files the held change is in, and that saying it was put back does not put it back.
function stillThere(report) {
  const files = (report.resting || []).join(", ") || "the files it named";
  return "Burrow checked again: the change it held is still in " + files + ", exactly as it was. " +
    "If you told the person you put the code back, you have not yet: put it back now, then say so. " +
    "If you are keeping the change, tell the person plainly that it is still there and which decision it goes against.";
}

function settings() {
  try { return JSON.parse(readFileSync(new URL("./burrow-gate.json", import.meta.url), "utf8")); } catch { return {}; }
}

function log(entry) {
  const file = process.env.BURROW_GATE_LOG;
  if (!file) return;
  try { appendFileSync(file, JSON.stringify({ program: "opencode", at: new Date().toISOString(), ...entry }) + "\n"); } catch {}
}

// Runs the check. Resolves to { code, report } or null when it could not run; a gate that cannot run never blocks.
function check(config) {
  return new Promise((resolve) => {
    const env = { ...process.env };
    if (config.stateDir) env.BURROW_STATE_DIR = config.stateDir;
    execFile(config.burrow || "burrow", ["check", config.vault, "--json"], { timeout: 20000, maxBuffer: 8 << 20, env },
      (error, stdout) => {
        const code = error ? (typeof error.code === "number" ? error.code : -1) : 0;
        let report = null;
        try { report = JSON.parse(String(stdout)); } catch {}
        resolve(report ? { code, report } : null);
      });
  });
}

// The message for a held change, or null when nothing is held.
function heldMessage(result) {
  if (!result) return null;
  const exit = typeof result.report.exit === "number" ? result.report.exit : result.code;
  if (![2, 3].includes(result.code) && ![2, 3].includes(exit)) return null;
  const broken = result.code === 3 || exit === 3;
  return (broken ? BROKEN + "\n\n" : "") + (result.report.text || "") + "\n\n" + NOTE;
}

export default {
  id: "burrow-gate",
  async setup(ctx) {
    const config = settings();
    if (!config.vault) return;
    const said = new Map();
    await ctx.session.hook("experimental.idle", async (event) => {
      const sessionID = event && event.sessionID;
      if (!sessionID) return;
      const before = said.get(sessionID) || [];
      if (before.length >= MOST_PER_SESSION) return;
      const result = await check(config);
      const message = heldMessage(result);
      const key = result && (result.report.fingerprint || result.report.text);
      log({ event: "idle", sessionID, exit: result ? result.code : null, held: Boolean(message) });
      const fingerprint = result && result.report.fingerprint;
      if (!message && fingerprint && before.includes(fingerprint) && !before.includes("still:" + fingerprint)) {
        said.set(sessionID, [...before, "still:" + fingerprint]);
        log({ event: "still", sessionID, fingerprint });
        await ctx.session.synthetic({ sessionID, text: stillThere(result.report), metadata: { source: "burrow-gate" } });
        return;
      }
      if (!message || before.includes(key)) return;
      said.set(sessionID, [...before, key]);
      log({ event: "held", sessionID, fingerprint: result.report.fingerprint, decisions: (result.report.decisions || []).map((d) => d.id) });
      await ctx.session.synthetic({ sessionID, text: message, metadata: { source: "burrow-gate" } });
    });
  },
};
