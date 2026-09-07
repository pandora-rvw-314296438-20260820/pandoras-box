import { spawnSync } from "node:child_process";

const checks = [
  ["mcp-inspector", ["--version"]],
  ["playwright", ["--version"]],
  ["biome", ["--version"]],
  ["supabase", ["--version"]],
  ["vercel", ["--version"]],
  ["knip", ["--version"]],
  ["posthog-cli", ["--version"]],
  ["gh", ["--version"]],
];

let failed = false;
for (const [command, args] of checks) {
  const result = spawnSync(command, args, { encoding: "utf8", shell: process.platform === "win32" });
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
