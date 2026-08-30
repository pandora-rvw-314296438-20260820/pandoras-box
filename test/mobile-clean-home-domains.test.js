const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");

const home=fs.readFileSync("apps/pandora-mobile/lib/features/simple/simple_home_screen.dart","utf8");
const shell=fs.readFileSync("apps/pandora-mobile/lib/app/pandora_shell.dart","utf8");
const model=fs.readFileSync("apps/pandora-mobile/lib/core/models/pandora_models.dart","utf8");
const owner=fs.readFileSync("supabase/functions/pandora-owner-api/index.ts","utf8");
const domains=fs.readFileSync("apps/pandora-mobile/lib/features/simple/domains_screen.dart","utf8");
const registrar=fs.readFileSync("apps/pandora-mobile/lib/core/data/domain_registrar_api.dart","utf8");

test("Simple Home is a clean dashboard, not a duplicate Pandora composer",()=>{
  assert.equal(home.includes("What do you want Pandora to do?"),false);
  assert.equal(home.includes("class _IntentCard"),false);
  for(const label of ["Start a new project","Projects","Domains","Needs You","Live"]){
    assert.equal(home.includes(label),true,`missing ${label}`);
  }
  assert.equal(home.includes("CreateProjectExperienceScreen"),true);
  assert.equal(home.includes("_homeProjectSummary(project)"),true);
  assert.equal(home.includes("maxLines: 2"),true);
  assert.equal(home.includes("Text(project.purpose"),false);
});

test("primary navigation reserves fifth destination for More",()=>{
  assert.equal(shell.includes("_Destination('More'"),true);
  assert.equal(shell.includes("4 => const MoreScreen()"),true);
  assert.equal(shell.includes("4 => 'more'"),true);
  assert.equal(shell.includes("_Destination('Business'"),false);
});

test("Home projection carries owner-safe domain truth",()=>{
  assert.equal(model.includes("class DomainSummary"),true);
  assert.equal(model.includes("bool get isLive => verified && status.toLowerCase() == 'ready'"),true);
  assert.equal(owner.includes("loadDomainSummaries(context, projectItems)"),true);
  assert.equal(owner.includes("domains: domainItems"),true);
});

test("domain purchase UI stays payment-gated until Xendit or PayPal is connected",()=>{
  assert.equal(domains.includes("class DomainAcquisitionScreen"),true);
  assert.equal(domains.includes("Find your domain"),true);
  assert.equal(domains.includes("Xendit"),true);
  assert.equal(domains.includes("PayPal"),true);
  assert.equal(domains.includes("Check payment"),true);
  assert.equal(domains.includes("Auto-renew is off for now"),true);
  assert.equal(/namecheap.*(?:token|secret|api.?key)/i.test(domains),false);
  assert.equal(domains.includes("RedApple"),false);
  assert.equal(registrar.includes("RedApple"),false);
  assert.equal(domains.includes("Pandora’s Box"),true);
  assert.equal(registrar.includes("Pandora’s Box"),true);
});
