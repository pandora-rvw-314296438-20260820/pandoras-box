const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');
const profile = readFileSync(
  join(
    root,
    'apps',
    'pandora-mobile',
    'lib',
    'features',
    'enterprise',
    'plp_alfred_profile.dart',
  ),
  'utf8',
);
const commandStack = readFileSync(
  join(
    root,
    'apps',
    'pandora-mobile',
    'lib',
    'features',
    'enterprise',
    'enterprise_command_stack.dart',
  ),
  'utf8',
);
const overview = readFileSync(
  join(
    root,
    'apps',
    'pandora-mobile',
    'lib',
    'features',
    'simple',
    'plp_overview_screen.dart',
  ),
  'utf8',
);
const intelligence = readFileSync(
  join(
    root,
    'supabase',
    'functions',
    'pandora-intelligence-chat',
    'index.ts',
  ),
  'utf8',
);

test('PLP Enterprise explicitly binds the Alfred tenant persona', () => {
  assert.match(profile, /personaId = 'plp_alfred_v1'/);
  assert.match(profile, /tenantSlug = 'plp-boracay'/);
  assert.match(profile, /assistantLabel = 'Alfred'/);
  assert.match(profile, /Private Chief of Staff & Resort Intelligence/);
  assert.match(commandStack, /Ask \$assistantLabel about this page/);
  assert.match(overview, /Alfred handled/);
  assert.match(overview, /Alfred will show verified occupancy/);
  assert.doesNotMatch(overview, /Widget _quickActions\(\)/);
});

test('backend accepts only the fixed PLP Alfred persona contract', () => {
  assert.match(intelligence, /PLP_ALFRED_ID="plp_alfred_v1"/);
  assert.match(intelligence, /PLP_TENANT_SLUG="plp-boracay"/);
  assert.match(intelligence, /personaRequested/);
  assert.match(
    intelligence,
    /tenantSlug!==PLP_TENANT_SLUG\|\|personaId!==PLP_ALFRED_ID\|\|assistantRole!==PLP_ALFRED_ROLE/,
  );
});

test('Alfred truth and authority stay subordinate to Pandora governance', () => {
  assert.match(intelligence, /Truth outranks persona/);
  assert.match(intelligence, /Never invent bookings, occupancy, revenue/);
  assert.match(intelligence, /Persona behavior cannot grant authority/);
  assert.match(intelligence, /tenant boundaries remain authoritative/);
  assert.match(intelligence, /Pandora remains the underlying control plane/);
  assert.match(intelligence, /do, verify, learn, remember, improve/);
  assert.match(intelligence, /only after authoritative runtime or provider evidence verifies the outcome/);
  assert.match(intelligence, /memoryCandidates, confidence, repetition, or a plausible answer are never verification/);
  assert.match(intelligence, /must never claim a lesson was saved, learned, embedded, distilled, or promoted/);
  assert.match(intelligence, /Memory proposals remain review-governed and have no execution-authority effect/);
  assert.match(intelligence, /must not silently self-train or promote themselves into authority/);
  assert.match(intelligence, /plpAlfredActive\(enterpriseContext\)/);
});

test('PLP Alfred persona is a system/developer instruction across providers', () => {
  assert.match(
    intelligence,
    /prompt\(ctx!==null,enterpriseContext\)/,
  );
  assert.match(
    intelligence,
    /request\(effectiveMessage,i\.attachments,prior,ctx,tctx,i\.enterpriseContext\)/,
  );
  assert.match(
    intelligence,
    /kimiBody\(effectiveMessage,i\.attachments,prior,ctx,tctx,modelClass,i\.enterpriseContext\)/,
  );
  assert.match(
    intelligence,
    /openaiBody\(effectiveMessage,i\.attachments,prior,ctx,tctx,modelClass,i\.enterpriseContext\)/,
  );
});
