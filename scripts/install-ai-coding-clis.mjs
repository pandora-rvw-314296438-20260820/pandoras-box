#!/usr/bin/env node
import { homedir, tmpdir } from "node:os";
import { join, delimiter } from "node:path";
import { mkdtempSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";

const verifyOnly = process.argv.includes("--verify-only");
const isWindows = process.platform === "win32";
const npmCommand = isWindows ? "npm.cmd" : "npm";

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    stdio: options.capture ? ["ignore", "pipe", "pipe"] : "inherit",
    encoding: "utf8",
    env: options.env ?? process.env,
    shell: false,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const detail = options.capture ? "\n" + (result.stderr || result.stdout || "") : "";
    throw new Error(command + " exited with status " + result.status + "." + detail);
  }
  return options.capture ? String(result.stdout || "").trim() : "";
}

function installNative(name, url) {
  const dir = mkdtempSync(join(tmpdir(), "pandora-" + name + "-"));
  try {
    if (isWindows) {
      const script = join(dir, name + "-install.ps1");
      const escaped = script.replaceAll("'", "''");
      run("powershell.exe", [
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command",
        "Invoke-WebRequest -UseBasicParsing -Uri '" + url + "' -OutFile '" + escaped + "'; & '" + escaped + "'",
      ]);
    } else {
      const script = join(dir, name + "-install.sh");
      run("curl", ["--proto", "=https", "--tlsv1.2", "-fsSL", url, "-o", script]);
      run("bash", [script]);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function toolEnv() {
  const prefix = run(npmCommand, ["config", "get", "prefix"], { capture: true });
  const home = homedir();
  const candidates = isWindows
    ? [prefix, join(home, ".local", "bin"), join(home, ".claude", "bin"), join(home, ".grok", "bin")]
    : [join(prefix, "bin"), join(home, ".local", "bin"), join(home, ".claude", "bin"), join(home, ".grok", "bin")];
  return { ...process.env, PATH: [...candidates, process.env.PATH || ""].join(delimiter) };
}

function verify(command) {
  run(command, ["--version"], { env: toolEnv() });
}

if (!verifyOnly) {
  run(npmCommand, ["install", "-g", "@openai/codex@latest", "@google/gemini-cli@latest"]);
  installNative("claude", isWindows ? "https://claude.ai/install.ps1" : "https://claude.ai/install.sh");
  installNative("grok", isWindows ? "https://x.ai/cli/install.ps1" : "https://x.ai/cli/install.sh");
}

for (const tool of ["codex", "claude", "gemini", "grok"]) verify(tool);

console.log("Pandora AI coding CLI toolchain is installed and version-verified.");
