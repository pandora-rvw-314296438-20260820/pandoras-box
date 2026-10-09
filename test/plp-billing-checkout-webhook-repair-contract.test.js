'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const repoRoot = path.join(__dirname, '..');
const migrationAPath = path.join(
  repoRoot,
  'supabase',
  'migrations',
  '20261010090000_plp_billing_checkout_hotfix_v1.sql'
);
const migrationBPath = path.join(
  repoRoot,
  'supabase',
  'migrations',
  '20261010091000_plp_paypal_webhook_ingest_v1.sql'
);
const rollbackAPath = path.join(
  repoRoot,
  'supabase',
  'rollback',
  '20261010090000_plp_billing_checkout_hotfix_v1.down.sql'
);
const rollbackBPath = path.join(
  repoRoot,
  'supabase',
  'rollback',
  '20261010091000_plp_paypal_webhook_ingest_v1.down.sql'
);
const oldCombinedPath = path.join(
  repoRoot,
  'supabase',
  'migrations',
  '20261010090000_plp_billing_checkout_webhook_repair_v1.sql'
);
const edgePath = path.join(
  repoRoot,
  'supabase',
  'functions',
  'pandora-plp-paypal-webhook',
  'index.ts'
);
const configPath = path.join(repoRoot, 'supabase', 'config.toml');

const migrationA = fs.readFileSync(migrationAPath, 'utf8');
const migrationB = fs.readFileSync(migrationBPath, 'utf8');
const rollbackA = fs.readFileSync(rollbackAPath, 'utf8');
const rollbackB = fs.readFileSync(rollbackBPath, 'utf8');
const edge = fs.readFileSync(edgePath, 'utf8');
const config = fs.readFileSync(configPath, 'utf8');

test('old combined migration file is deleted', () => {
  assert.equal(
    fs.existsSync(oldCombinedPath),
    false,
    'supabase/migrations/20261010090000_plp_billing_checkout_webhook_repair_v1.sql must be deleted'
  );
});

test('migration A header comment marks status as NOT APPLIED, cites defect evidence, and names rollback', () => {
  assert.match(migrationA, /NOT APPLIED\s*—\s*requires owner approval/i);
  assert.match(
    migrationA,
    /column "created_by" of relation "pandora_paypal_billing_sessions" does not exist/
  );
  assert.match(migrationA, /2026-10-09T19:02:11Z/);
  assert.match(migrationA, /42703/);
  assert.match(migrationA, /S1/);
  assert.match(migrationA, /S2/);
  assert.match(migrationA, /S4/);
  assert.match(migrationA, /reconcile CHECK violation on 'provider_verified'/i);
  assert.match(
    migrationA,
    /supabase\/rollback\/20261010090000_plp_billing_checkout_hotfix_v1\.down\.sql/
  );
  assert.doesNotMatch(migrationA, /^\s*begin\s*;/im);
  assert.doesNotMatch(migrationA, /^\s*commit\s*;/im);
});

test('migration A contains only the 3 functions, no cron, no table DDL, and errcode 23505', () => {
  const fnMatches = [
    ...migrationA.matchAll(/create or replace function ([a-zA-Z0-9_.]+)\s*\(/gi),
  ];
  assert.equal(fnMatches.length, 3, 'Migration A must contain exactly 3 functions');
  const fnNames = fnMatches.map((m) => m[1].toLowerCase());
  assert.deepEqual(
    fnNames,
    [
      'public.pandora_plp_billing_checkout_v1',
      'public.pandora_plp_billing_reconcile_v1',
      'public.pandora_plp_billing_status_v1',
    ],
    'Must only contain the 3 checkout hotfix functions'
  );

  // Must not touch cron, create table, alter table, or drop
  assert.doesNotMatch(migrationA, /cron\./i, 'Migration A must not touch cron');
  assert.doesNotMatch(migrationA, /create\s+table/i, 'Migration A must not create tables');
  assert.doesNotMatch(migrationA, /alter\s+table/i, 'Migration A must not alter tables');
  assert.doesNotMatch(migrationA, /drop\s+/i, 'Migration A must not drop anything');

  // Assert 23505 for SUBSCRIPTION_ALREADY_ACTIVE
  assert.match(
    migrationA,
    /raise exception 'SUBSCRIPTION_ALREADY_ACTIVE' using errcode\s*=\s*'23505';/
  );
  assert.doesNotMatch(
    migrationA,
    /raise exception 'SUBSCRIPTION_ALREADY_ACTIVE' using errcode\s*=\s*'P0002';/
  );
});

test('migration B documents dependency on A and contains webhook pieces and cron', () => {
  assert.match(migrationB, /NOT APPLIED\s*—\s*requires owner approval/i);
  assert.match(
    migrationB,
    /depends on (20261010090000_plp_billing_checkout_hotfix_v1\.sql|A)/i
  );
  assert.match(migrationB, /changes nothing user-visible until the edge function is deployed/i);
  assert.match(migrationB, /S3/);

  const fnMatches = [
    ...migrationB.matchAll(/create or replace function ([a-zA-Z0-9_.]+)\s*\(/gi),
  ];
  assert.equal(fnMatches.length, 3, 'Migration B must contain exactly 3 functions');
  const fnNames = fnMatches.map((m) => m[1].toLowerCase());
  assert.deepEqual(
    fnNames,
    [
      'private.pandora_paypal_verify_webhook_v1',
      'public.pandora_plp_paypal_webhook_ingest_v1',
      'private.pandora_plp_billing_reconcile_open_v1',
    ]
  );

  assert.match(
    migrationB,
    /cron\.schedule\(\s*'pandora-plp-billing-reconcile-v1',\s*'\*\/10 \* \* \* \*'/
  );

  assert.doesNotMatch(migrationB, /^\s*begin\s*;/im);
  assert.doesNotMatch(migrationB, /^\s*commit\s*;/im);
});

test('rollback files exist and A-down contains the 3 live definitions', () => {
  assert.ok(fs.existsSync(rollbackAPath), 'Rollback file A must exist');
  assert.ok(fs.existsSync(rollbackBPath), 'Rollback file B must exist');

  // A-down contains the 3 live definitions from live snapshot
  assert.match(rollbackA, /CREATE OR REPLACE FUNCTION public\.pandora_plp_billing_checkout_v1/i);
  assert.match(rollbackA, /CREATE OR REPLACE FUNCTION public\.pandora_plp_billing_reconcile_v1/i);
  assert.match(rollbackA, /CREATE OR REPLACE FUNCTION public\.pandora_plp_billing_status_v1/i);

  // Live snapshot had created_by and status = 'provider_verified'
  assert.match(rollbackA, /insert into public\.pandora_paypal_billing_sessions[^;]*created_by/i);
  assert.match(rollbackA, /status\s*=\s*'provider_verified'/i);

  // B-down unschedules pg_cron and drops B functions
  assert.match(rollbackB, /cron\.unschedule/i);
  assert.match(rollbackB, /pandora-plp-billing-reconcile-v1/);
  assert.match(
    rollbackB,
    /drop function if exists public\.pandora_plp_paypal_webhook_ingest_v1\(jsonb,\s*text\);/i
  );
  assert.match(
    rollbackB,
    /drop function if exists private\.pandora_paypal_verify_webhook_v1\(jsonb,\s*text\);/i
  );
  assert.match(
    rollbackB,
    /drop function if exists private\.pandora_plp_billing_reconcile_open_v1\(int\);/i
  );
});

test('checkout insert names valid columns and never references created_by, error_message, or provider_reference on sessions', () => {
  // Extract checkout_v1 function body from migration A
  const fnMatch = migrationA.match(
    /create or replace function public\.pandora_plp_billing_checkout_v1[\s\S]*?\$function\$;/i
  );
  assert.ok(fnMatch, 'pandora_plp_billing_checkout_v1 function must exist');
  const checkoutFn = fnMatch[0];

  // Insert into pandora_paypal_billing_sessions must name required columns
  assert.match(
    checkoutFn,
    /insert into public\.pandora_paypal_billing_sessions\s*\(\s*[^)]*requested_by/i
  );
  assert.match(
    checkoutFn,
    /insert into public\.pandora_paypal_billing_sessions\s*\(\s*[^)]*plan_code/i
  );
  assert.match(
    checkoutFn,
    /insert into public\.pandora_paypal_billing_sessions\s*\(\s*[^)]*paypal_plan_id/i
  );
  assert.match(
    checkoutFn,
    /insert into public\.pandora_paypal_billing_sessions\s*\(\s*[^)]*return_url/i
  );
  assert.match(
    checkoutFn,
    /insert into public\.pandora_paypal_billing_sessions\s*\(\s*[^)]*cancel_url/i
  );

  // Must NEVER reference non-existent columns on pandora_paypal_billing_sessions
  assert.doesNotMatch(
    checkoutFn,
    /created_by|error_message|provider_reference/i
  );

  // Across the entire migration A, pandora_paypal_billing_sessions operations never use created_by or error_message
  assert.doesNotMatch(
    migrationA,
    /insert into public\.pandora_paypal_billing_sessions[^;]*created_by/i
  );
  assert.doesNotMatch(
    migrationA,
    /update public\.pandora_paypal_billing_sessions[^;]*(created_by|error_message|provider_reference)/i
  );
});

test('every session status literal written in the migration is in the CHECK set', () => {
  const allowedStatuses = new Set([
    'created',
    'approval_pending',
    'active',
    'cancel_requested',
    'cancelled',
    'suspended',
    'expired',
    'failed',
  ]);

  // Find all status assignments and values for pandora_paypal_billing_sessions in migration A
  const updateMatches = [
    ...migrationA.matchAll(
      /update public\.pandora_paypal_billing_sessions[\s\S]*?set[\s\S]*?status\s*=\s*'([^']+)'/gi
    ),
  ];
  assert.ok(updateMatches.length > 0, 'Must have updates to session status');
  for (const m of updateMatches) {
    const status = m[1];
    assert.ok(
      allowedStatuses.has(status),
      `Status literal '${status}' in update must be in CHECK set`
    );
  }

  // Check insert status value
  const insertStatusMatches = [
    ...migrationA.matchAll(
      /insert into public\.pandora_paypal_billing_sessions[\s\S]*?values\s*\([^;]*?'(created|approval_pending|active|cancel_requested|cancelled|suspended|expired|failed)'/gi
    ),
  ];
  assert.ok(
    insertStatusMatches.length > 0,
    'Must insert status in the allowed CHECK set'
  );
});

test('reconcile never writes provider_verified into a session status and sets active on confirmation', () => {
  const fnMatch = migrationA.match(
    /create or replace function public\.pandora_plp_billing_reconcile_v1[\s\S]*?\$function\$;/i
  );
  assert.ok(fnMatch, 'pandora_plp_billing_reconcile_v1 function must exist');
  const reconcileFn = fnMatch[0];

  // Must NEVER set status = 'provider_verified'
  assert.doesNotMatch(reconcileFn, /status\s*=\s*'provider_verified'/i);

  // Must update status to 'active' on ACTIVE provider state
  assert.match(
    reconcileFn,
    /update public\.pandora_paypal_billing_sessions\s+set status = 'active'/i
  );
});

test("migration A contains no 'default null' / 'default' on reconcile parameters", () => {
  const fnMatch = migrationA.match(
    /create or replace function public\.pandora_plp_billing_reconcile_v1\s*\(([\s\S]*?)\)\s*returns/i
  );
  assert.ok(fnMatch, 'pandora_plp_billing_reconcile_v1 function must exist');
  const params = fnMatch[1];
  assert.doesNotMatch(
    params,
    /default\s+null/i,
    "reconcile parameters must not contain 'default null'"
  );
  assert.doesNotMatch(
    params,
    /\bdefault\b/i,
    "reconcile parameters must not contain 'default'"
  );
});

test('ACTIVE provider state sets request_admission_enabled to true and records admission anchor', () => {
  const fnMatch = migrationA.match(
    /create or replace function public\.pandora_plp_billing_reconcile_v1[\s\S]*?\$function\$;/i
  );
  assert.ok(fnMatch, 'pandora_plp_billing_reconcile_v1 function must exist');
  const reconcileFn = fnMatch[0];

  assert.match(reconcileFn, /request_admission_enabled\s*=\s*true/i);
  assert.match(
    reconcileFn,
    /coalesce\([^)]*request_admission_started_at,\s*now\(\)\)/i
  );
});

test('SUSPENDED and EXPIRED/CANCELLED provider states are handled by reconcile', () => {
  const fnMatch = migrationA.match(
    /create or replace function public\.pandora_plp_billing_reconcile_v1[\s\S]*?\$function\$;/i
  );
  assert.ok(fnMatch, 'pandora_plp_billing_reconcile_v1 function must exist');
  const reconcileFn = fnMatch[0];

  // SUSPENDED branch
  assert.match(reconcileFn, /v_provider_state\s*=\s*'SUSPENDED'/i);
  assert.match(reconcileFn, /state\s*=\s*'suspended'/i);
  assert.match(reconcileFn, /request_admission_enabled\s*=\s*false/i);
  assert.match(reconcileFn, /status\s*=\s*'suspended'/i);

  // CANCELLED / EXPIRED branch
  assert.match(reconcileFn, /v_provider_state\s+in\s*\('CANCELLED',\s*'EXPIRED'\)/i);
  assert.match(reconcileFn, /state\s*=\s*'cancelled'/i);
  assert.match(reconcileFn, /ends_on\s*=\s*greatest\(/i);
  assert.match(reconcileFn, /status\s*=\s*'cancelled'/i);
});

test('checkout serialises concurrent requests using advisory transaction lock', () => {
  assert.match(
    migrationA,
    /perform pg_advisory_xact_lock\(hashtextextended\('plp-billing-checkout:'\s*\|\|\s*p_organization_id::text,\s*0\)\);/
  );
});

test('webhook ingest verifies signature before any event insert or reconcile call', () => {
  const fnMatch = migrationB.match(
    /create or replace function public\.pandora_plp_paypal_webhook_ingest_v1[\s\S]*?\$function\$;/i
  );
  assert.ok(fnMatch, 'pandora_plp_paypal_webhook_ingest_v1 function must exist');
  const ingestFn = fnMatch[0];

  const verifyIdx = ingestFn.indexOf('private.pandora_paypal_verify_webhook_v1');
  const insertIdx = ingestFn.indexOf(
    'insert into public.pandora_paypal_billing_webhook_events'
  );
  const reconcileIdx = ingestFn.indexOf(
    'public.pandora_plp_billing_reconcile_v1'
  );

  assert.ok(verifyIdx > 0, 'Signature verification call must exist');
  assert.ok(insertIdx > 0, 'Event insert must exist');
  assert.ok(reconcileIdx > 0, 'Reconcile call must exist');

  assert.ok(
    verifyIdx < insertIdx,
    'Signature verification must precede table insert'
  );
  assert.ok(
    verifyIdx < reconcileIdx,
    'Signature verification must precede reconcile invocation'
  );
});

test('webhook ingest never derives subscription state from event_type and only calls reconcile', () => {
  const fnMatch = migrationB.match(
    /create or replace function public\.pandora_plp_paypal_webhook_ingest_v1[\s\S]*?\$function\$;/i
  );
  assert.ok(fnMatch, 'pandora_plp_paypal_webhook_ingest_v1 function must exist');
  const ingestFn = fnMatch[0];

  // Ingest must not perform subscription DML directly
  assert.doesNotMatch(
    ingestFn,
    /update public\.pandora_customer_subscriptions/i
  );
  assert.doesNotMatch(
    ingestFn,
    /insert into public\.pandora_customer_subscriptions/i
  );

  // Ingest delegates state sync to reconcile_v1
  assert.match(
    ingestFn,
    /public\.pandora_plp_billing_reconcile_v1\(v_org_id,\s*null\)/
  );
});

test('functions grant execute to service_role and revoke from public, anon, and authenticated', () => {
  const publicHotfixFunctions = [
    'pandora_plp_billing_checkout_v1',
    'pandora_plp_billing_reconcile_v1',
    'pandora_plp_billing_status_v1',
  ];

  for (const fn of publicHotfixFunctions) {
    const revokeRegex = new RegExp(
      `revoke all on function public\\.${fn}[\\s\\S]*?from public,\\s*anon,\\s*authenticated;`,
      'i'
    );
    assert.match(migrationA, revokeRegex, `Revoke statement missing for ${fn}`);

    const grantRegex = new RegExp(
      `grant execute on function public\\.${fn}[\\s\\S]*?to [^;]*service_role;`,
      'i'
    );
    assert.match(migrationA, grantRegex, `Grant statement missing for ${fn}`);

    const badGrantRegex = new RegExp(
      `grant execute on function public\\.${fn}[\\s\\S]*?to [^;]*(anon|authenticated)[^;]*;`,
      'i'
    );
    assert.doesNotMatch(
      migrationA,
      badGrantRegex,
      `Should not grant execute to anon/authenticated for ${fn}`
    );
  }

  // Webhook ingest function in migration B
  const revokeIngestRegex = new RegExp(
    `revoke all on function public\\.pandora_plp_paypal_webhook_ingest_v1[\\s\\S]*?from public,\\s*anon,\\s*authenticated;`,
    'i'
  );
  assert.match(migrationB, revokeIngestRegex, 'Revoke statement missing for pandora_plp_paypal_webhook_ingest_v1');

  const grantIngestRegex = new RegExp(
    `grant execute on function public\\.pandora_plp_paypal_webhook_ingest_v1[\\s\\S]*?to [^;]*service_role;`,
    'i'
  );
  assert.match(migrationB, grantIngestRegex, 'Grant statement missing for pandora_plp_paypal_webhook_ingest_v1');

  // Private functions in migration B revoked from public, anon, authenticated
  for (const fn of [
    'pandora_paypal_verify_webhook_v1',
    'pandora_plp_billing_reconcile_open_v1',
  ]) {
    const revokeRegex = new RegExp(
      `revoke all on function private\\.${fn}[\\s\\S]*?from public,\\s*anon,\\s*authenticated;`,
      'i'
    );
    assert.match(migrationB, revokeRegex, `Revoke statement missing for ${fn}`);
  }
});

test('config.toml configures pandora-plp-paypal-webhook with verify_jwt = false', () => {
  assert.match(
    config,
    /\[functions\.pandora-plp-paypal-webhook\][\s\S]*?verify_jwt\s*=\s*false/
  );
});

test('edge function does not console.log body or headers and only logs structured code', () => {
  // Should not log sensitive raw data
  assert.doesNotMatch(
    edge,
    /console\.(log|error|info|warn)\([^)]*(rawBody|headers|req\.headers|p_headers|p_raw_body)/i
  );

  // Only logs { code }
  const logMatches = [...edge.matchAll(/console\.error\(([^)]+)\)/g)];
  assert.ok(logMatches.length > 0, 'Console error calls expected for failures');
  for (const m of logMatches) {
    assert.match(
      m[1],
      /JSON\.stringify\(\{\s*code/i,
      `Log statement must only output { code }: ${m[1]}`
    );
  }
});

test('signature verification uses exact raw body bytes without re-serialising jsonb', () => {
  const verifyFnMatch = migrationB.match(
    /create or replace function private\.pandora_paypal_verify_webhook_v1\s*\(\s*p_headers\s+jsonb,\s*p_raw_body\s+text\s*\)[\s\S]*?\$function\$;/i
  );
  assert.ok(
    verifyFnMatch,
    'pandora_paypal_verify_webhook_v1 must accept (p_headers jsonb, p_raw_body text)'
  );
  const verifyFn = verifyFnMatch[0];

  // Request body must be built as TEXT embedding exact raw body bytes
  assert.match(
    verifyFn,
    /rtrim\(jsonb_build_object\([\s\S]*?\)::text,\s*'}'\)\s*\|\|\s*', "webhook_event": '\s*\|\|\s*p_raw_body\s*\|\|\s*'}'/
  );

  // Ingest caller must pass p_raw_body to verification
  const ingestFnMatch = migrationB.match(
    /create or replace function public\.pandora_plp_paypal_webhook_ingest_v1[\s\S]*?\$function\$;/i
  );
  assert.ok(ingestFnMatch, 'pandora_plp_paypal_webhook_ingest_v1 function must exist');
  assert.match(
    ingestFnMatch[0],
    /private\.pandora_paypal_verify_webhook_v1\(p_headers,\s*p_raw_body\)/
  );

  // Revoke/grant must use (jsonb, text) signature
  assert.match(
    migrationB,
    /revoke all on function private\.pandora_paypal_verify_webhook_v1\(jsonb,\s*text\)\s+from public,\s*anon,\s*authenticated;/i
  );
  assert.match(
    migrationB,
    /grant execute on function private\.pandora_paypal_verify_webhook_v1\(jsonb,\s*text\)\s+to postgres,\s*service_role;/i
  );
});

test('reconcile prefers newest session reference when existing subscription is null or cancelled', () => {
  const fnMatch = migrationA.match(
    /create or replace function public\.pandora_plp_billing_reconcile_v1[\s\S]*?\$function\$;/i
  );
  assert.ok(fnMatch, 'pandora_plp_billing_reconcile_v1 function must exist');
  const reconcileFn = fnMatch[0];

  assert.match(
    reconcileFn,
    /if\s*\(\s*v_sub\s+is\s+null\s+or\s+v_sub\.state\s*=\s*'cancelled'\s*\)\s*and\s*v_session\.created_at\s*>\s*coalesce\(v_sub\.updated_at,\s*'-infinity'\)\s*then/i
  );
  assert.match(
    reconcileFn,
    /v_reference\s*:=\s*coalesce\(v_session\.paypal_subscription_id,\s*v_sub\.provider_reference,\s*v_change\.paypal_subscription_id\);/i
  );
  assert.match(
    reconcileFn,
    /v_reference\s*:=\s*coalesce\(v_sub\.provider_reference,\s*v_session\.paypal_subscription_id,\s*v_change\.paypal_subscription_id\);/i
  );
});

test('checkout rolls back entire attempt on provider failure for clean idempotency retries', () => {
  const fnMatch = migrationA.match(
    /create or replace function public\.pandora_plp_billing_checkout_v1[\s\S]*?\$function\$;/i
  );
  assert.ok(fnMatch, 'pandora_plp_billing_checkout_v1 function must exist');
  const checkoutFn = fnMatch[0];

  // Must not have pointless status='failed' update immediately before raising PAYPAL_CHECKOUT_FAILED
  assert.doesNotMatch(
    checkoutFn,
    /update public\.pandora_paypal_billing_sessions[\s\S]*?status\s*=\s*'failed'[\s\S]*?raise exception 'PAYPAL_CHECKOUT_FAILED'/i
  );

  // Must explain that the whole attempt is rolled back on purpose for idempotency retry
  assert.match(
    checkoutFn,
    /The whole attempt is rolled back on purpose so a retry with the same\s+-- idempotency key starts clean and PayPal dedupes on paypal-request-id = session id/i
  );
});
