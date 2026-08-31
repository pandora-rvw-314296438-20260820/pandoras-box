const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const home = fs.readFileSync(
  "apps/pandora-mobile/lib/features/simple/simple_home_screen.dart",
  "utf8",
);
const shell = fs.readFileSync(
  "apps/pandora-mobile/lib/app/pandora_shell.dart",
  "utf8",
);
const model = fs.readFileSync(
  "apps/pandora-mobile/lib/core/models/pandora_models.dart",
  "utf8",
);
const owner = fs.readFileSync(
  "supabase/functions/pandora-owner-api/index.ts",
  "utf8",
);
const domains = fs.readFileSync(
  "apps/pandora-mobile/lib/features/simple/domains_screen.dart",
  "utf8",
);
const registrar = fs.readFileSync(
  "apps/pandora-mobile/lib/core/data/domain_registrar_api.dart",
  "utf8",
);

test("Simple Home makes customer intent and current projects the interface", () => {
  assert.equal(home.includes("What do you want\\nto make happen?"), true);
  assert.equal(home.includes("PandoraV2IntentSurface"), true);
  assert.equal(home.includes("CreateProjectExperienceScreen"), true);
  assert.equal(home.includes("'Your projects'"), true);
  assert.equal(home.includes("'Needs you'"), true);
  assert.equal(home.includes("DomainsScreen"), false);
  assert.equal(home.includes("What do you want Pandora to do?"), false);
  assert.equal(home.includes("class _IntentCard"), false);
});

test("primary navigation is reduced to Home, Work, and Needs You", () => {
  assert.equal(shell.includes("_Destination('Home'"), true);
  assert.equal(shell.includes("_Destination('Work'"), true);
  assert.equal(shell.includes("'Needs You'"), true);
  assert.equal(shell.includes("1 => 'work'"), true);
  assert.equal(shell.includes("2 => 'needs_you'"), true);
  assert.equal(shell.includes("_Destination('More'"), false);
  assert.equal(shell.includes("'Ask Pandora'"), false);
  assert.equal(shell.includes("AskPandoraScreen"), false);
  assert.equal(shell.includes("MoreScreen"), false);
});

test("Home projection carries owner-safe domain truth", () => {
  assert.equal(model.includes("class DomainSummary"), true);
  assert.equal(
    model.includes(
      "bool get isLive => verified && status.toLowerCase() == 'ready'",
    ),
    true,
  );
  assert.equal(owner.includes("loadDomainSummaries(context, projectItems)"), true);
  assert.equal(owner.includes("domains: domainItems"), true);
});

test("domain purchase UI stays payment-gated until Xendit or PayPal is connected", () => {
  assert.equal(domains.includes("class DomainAcquisitionScreen"), true);
  assert.equal(domains.includes("Find your domain"), true);
  assert.equal(domains.includes("Xendit"), true);
  assert.equal(domains.includes("PayPal"), true);
  assert.equal(domains.includes("Check payment"), true);
  assert.equal(domains.includes("Auto-renew is off for now"), true);
  assert.equal(/namecheap.*(?:token|secret|api.?key)/i.test(domains), false);
  assert.equal(domains.includes("RedApple"), false);
  assert.equal(registrar.includes("RedApple"), false);
  assert.equal(domains.includes("Pandora’s Box"), true);
  assert.equal(registrar.includes("Pandora’s Box"), true);
});
