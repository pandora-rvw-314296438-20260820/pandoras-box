"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const config = fs.readFileSync("supabase/config.toml", "utf8");
const migration = fs.readFileSync(
  "supabase/migrations/20260910140000_pandora_base44_bridge_release_allowlist_v1.sql",
  "utf8",
);
const deployFrozen = JSON.parse(
  fs.readFileSync("supabase/functions/DEPLOY_FROZEN.json", "utf8"),
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
  const frozenSlugs = new Set(deployFrozen.slugs);
  for (const slug of disabled) {
    const hasAllowlist =
      new RegExp(`when '${slug.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}' then`).test(migration) &&
      new RegExp(`supabase/functions/${slug.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}/index\\.ts`).test(migration);
    const isFrozen = frozenSlugs.has(slug);
    assert.ok(
      hasAllowlist || isFrozen,
      `disabled function ${slug} must either have an exact-source release allowlist case or be listed in DEPLOY_FROZEN.json`,
    );
    if (!isFrozen) {
      assert.match(
        migration,
        new RegExp(`when '${slug.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}' then`),
        `missing exact-source release allowlist case for ${slug}`,
      );
      assert.match(
        migration,
        new RegExp(`supabase/functions/${slug.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}/index\\.ts`),
        `missing exact source path for ${slug}`,
      );
    }
  }
});

test("every supabase/functions/*/index.ts folder is declared in config.toml with enabled = false", () => {
  const disabled = new Set(disabledFunctionSlugs(config));
  const functionsDir = "supabase/functions";
  const functionFolders = fs
    .readdirSync(functionsDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && fs.existsSync(path.join(functionsDir, entry.name, "index.ts")))
    .map((entry) => entry.name)
    .sort();

  assert.ok(functionFolders.length > 0, "functions directory must contain function folders");
  for (const folder of functionFolders) {
    assert.ok(
      disabled.has(folder),
      `expected ${folder} to be declared in config.toml with enabled = false so integration deploys nothing`,
    );
  }
});

test("every DEPLOY_FROZEN slug has supabase/functions/<slug>/index.ts and is disabled in config.toml", () => {
  const disabled = new Set(disabledFunctionSlugs(config));
  assert.ok(Array.isArray(deployFrozen.slugs) && deployFrozen.slugs.length > 0);
  assert.deepEqual(
    deployFrozen.slugs,
    [...deployFrozen.slugs].sort(),
    "DEPLOY_FROZEN slugs must be sorted",
  );
  for (const slug of deployFrozen.slugs) {
    const indexPath = path.join("supabase/functions", slug, "index.ts");
    assert.ok(
      fs.existsSync(indexPath),
      `expected ${indexPath} to exist for DEPLOY_FROZEN slug ${slug}`,
    );
    assert.ok(
      disabled.has(slug),
      `expected DEPLOY_FROZEN slug ${slug} to be disabled in config.toml`,
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
