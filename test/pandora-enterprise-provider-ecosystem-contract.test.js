"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const { test } = require("node:test");

const root = join(__dirname, "..");
const shell = readFileSync(
  join(root, "apps/pandora-mobile/lib/app/pandora_chat_shell.dart"),
  "utf8",
);
const screen = [
  "provider_ecosystem_screen.dart",
  "provider_ecosystem_catalog.dart",
].map((name) => readFileSync(
  join(root, "apps/pandora-mobile/lib/features/enterprise", name),
  "utf8",
)).join("\n");
const plpMain = readFileSync(
  join(root, "apps/pandora-mobile/lib/main_plp.dart"),
  "utf8",
);
const plpShell = readFileSync(
  join(root, "apps/pandora-mobile/lib/app/plp_enterprise_shell.dart"),
  "utf8",
);

test("Pandora Enterprise exposes the universal provider ecosystem", () => {
  assert.match(shell, /provider_ecosystem_screen\.dart/);
  assert.match(shell, /Capabilities & Providers/);
  assert.match(shell, /ProviderEcosystemScreen/);
  assert.match(shell, /Live Connections/);

  for (const capability of [
    "Compute",
    "Data",
    "Telecom",
    "Communications",
    "Marketing",
    "Commerce",
    "Money",
    "Logistics",
    "Identity",
    "Government",
    "Location",
    "Documents",
    "Security",
    "Devices",
    "Intelligence",
  ]) {
    assert.match(screen, new RegExp("name: '" + capability + "'"));
  }

  for (const provider of [
    "AWS",
    "Supabase",
    "PLDT Enterprise",
    "Vonage",
    "Meta/Facebook Ads",
    "Voluum",
    "Grab",
    "Maya",
    "Ubivelox Philippines",
    "Shopify",
    "Google Maps",
    "Xero",
    "DocuSign",
    "SEC Philippines",
    "Android",
    "local/on-device AI",
  ]) {
    assert.match(screen, new RegExp(provider.replace(/[-/\\^$*+?.()|[\]{}]/g, "\\$&")));
  }
});

test("catalog semantics remain fail-closed and PLP stays isolated", () => {
  assert.match(screen, /Catalog presence never means connected or executable/);
  assert.match(screen, /verifies authorization, account scope, jurisdiction, provider health and availability before execution/);
  assert.match(screen, /Future providers plug into these capabilities/);

  assert.doesNotMatch(plpMain, /ProviderEcosystemScreen|Capabilities & Providers/);
  assert.doesNotMatch(plpShell, /ProviderEcosystemScreen|Capabilities & Providers/);
});
