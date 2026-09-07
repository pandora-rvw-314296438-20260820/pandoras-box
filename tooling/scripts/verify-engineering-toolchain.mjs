import { accessSync, constants } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";

const binName = process.platform === "win32" ? "mcp-inspector.cmd" : "mcp-inspector";
const inspectorPath = path.join(process.cwd(), "node_modules", ".bin", binName);
let failed = false;

try {
  accessSync(inspectorPath, constants.X_OK);
  console.log("[toolchain] mcp-inspector: installed; exercised separately by npm run mcp:inspect");
} catch {
  failed = true;
  console.error("[toolchain] mcp-inspector: unavailable");
}

const checks = [
  ["playwright", ["--version"]],
  ["biome", ["--version"]],
  ["supabase", ["--version"]],
  ["vercel", ["--version"]],
  ["knip", ["--version"]],
  ["posthog-cli", ["--version"]],
  ["gh", ["--version"]],
];

for (const [command, args] of checks) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    shell: process.platform === "win32",
    timeout: 10_000,
  });
  if (result.error?.code === "ETIMEDOUT" || result.signal === "SIGTERM") {
    failed = true;
    console.error(`[toolchain] ${command}: timed out`);
    continue;
  }
  if (result.status !== 0) {
    failed = true;
    console.error(`[toolchain] ${command}: unavailable`);
    if (result.stderr) console.error(result.stderr.trim());
    continue;
  }
  const output = (result.stdout || result.stderr || "").trim().split("\n")[0];
  console.log(`[toolchain] ${command}: ${output || "ok"}`);
}

if (failed) process.exit(1);
