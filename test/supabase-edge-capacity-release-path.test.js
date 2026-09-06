"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");

const config = fs.readFileSync("supabase/config.toml", "utf8");
const migration = fs.readFileSync(
  "supabase/migrations/20260906050000_pandora_declared_edge_release_allowlist_v1.sql",
  "utf8",
);

function disabledFunctionSlugs(text) {
  const lines = text.split(/\r?\n/);
  const slugs = [];
  let current = null;
  for (const line of lines) {
    const header = line.match(/^\[functions\.([^\]]+)\]$/);
    if (header) {
      current = header[1];
      continue;
    }
    if (current && /^enabled\s*=\s*false\s*$/.test(line.trim())) {
      slugs.push(current);
    }
  }
  return slugs.sort();
}

test("every capacity-skipped Edge function retains an exact-source release path", () => {
  const disabled = disabledFunctionSlugs(config);
  assert.ok(disabled.length > 0, "capacity workaround must explicitly declare skipped functions");
  for (const slug of disabled) {
    assert.match(
      migration,
      new RegExp(`when '${slug.replace(/[.*+?^$\{\}()|[\]\\]/g, "\\$&")}' then`),
      `missing exact-source release allowlist case for ${slug}`,
    );
    assert.match(
      migration,
      new RegExp(`supabase/functions/${slug.replace(/[.*+?^$\{\}()|[\]\\]/g, "\\$&")}/index\\.ts`),
      `missing exact source path for ${slug}`,
    );
  }
});

test("capacity workaround preserves the fail-closed exact release boundary", () => {
  assert.match(migration, /exact GitHub commit SHA required/);
  assert.match(migration, /Edge function slug outside Pandora release allowlist/);
  assert.match(migration, /exact Edge source unavailable at requested commit/);
  assert.match(migration, /Supabase Edge deployment failed with status/);
  assert.doesNotMatch(migration, /from public\.memory_context_packs/i);
});
