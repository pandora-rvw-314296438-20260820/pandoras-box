"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");

const root = join(__dirname, "..");
const api = readFileSync(
  join(root, "apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart"),
  "utf8",
);
const plugins = readFileSync(
  join(root, "apps/pandora-mobile/lib/features/plugins/plugins_screen.dart"),
  "utf8",
);
const catalog = readFileSync(
  join(
    root,
    "apps/pandora-mobile/lib/features/plugins/provider_catalog_screen.dart",
  ),
  "utf8",
);

test("mobile provider marketplace reads the governed Universal catalog", () => {
  assert.match(api, /Future<List<PandoraProviderCatalogEntry>> providerCatalog\(\)/);
  assert.match(api, /pandora_provider_catalog_v1/);
  assert.match(api, /class PandoraProviderCatalogEntry/);
  assert.match(api, /class PandoraProviderCatalogCapability/);

  assert.match(plugins, /Browse provider catalog/);
  assert.match(plugins, /ProviderCatalogScreen/);
  assert.match(catalog, /Universal provider marketplace/);
  assert.match(catalog, /Availability never means connected/);
  assert.match(catalog, /provider-backed readback/);
  assert.match(catalog, /AskPandoraScreen/);
});

test("catalog-only discovery never claims a provider is connected", () => {
  assert.doesNotMatch(catalog, /return 'Connected'/);
  assert.match(catalog, /Authorized · healthy/);
  assert.match(catalog, /Available · authorization required/);
  assert.match(catalog, /do not claim connected until provider-backed readback succeeds/);
});
