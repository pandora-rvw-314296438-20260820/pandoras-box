"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const ROOT = path.resolve(__dirname, "..");
const TEXT_EXTENSIONS = new Set([".js",".mjs",".cjs",".ts",".tsx",".jsx",".json",".md",".sql",".yml",".yaml",".toml",".txt",".html",".css",".dart",".sh",".ps1",".xml",".env",".example"]);
const SKIP_DIRS = new Set([".git","node_modules",".next","dist","build","coverage",".dart_tool"]);
const retired = "project" + "os";
const variants = [retired, "project" + "-os", "project" + "_os", "project" + " os"];

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory() && SKIP_DIRS.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out); else if (entry.isFile()) out.push(full);
  }
  return out;
}

test("retired control-plane identity is absent from repository paths and text", () => {
  const hits = [];
  for (const file of walk(ROOT)) {
    const rel = path.relative(ROOT, file).replaceAll(path.sep, "/");
    const lowerPath = rel.toLowerCase();
    for (const token of variants) if (lowerPath.includes(token)) hits.push(rel + ":path:" + token);
    const ext = path.extname(rel).toLowerCase();
    if (!TEXT_EXTENSIONS.has(ext) && !["Dockerfile","Makefile","Procfile"].includes(path.basename(rel))) continue;
    let content;
    try { content = fs.readFileSync(file, "utf8").toLowerCase(); } catch { continue; }
    for (const token of variants) if (content.includes(token)) hits.push(rel + ":content:" + token);
  }
  assert.deepEqual(hits, [], "Retired control-plane traces remain:\n" + hits.slice(0, 400).join("\n"));
});
